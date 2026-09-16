# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/tarazed/windows/conpty"

class WindowsConPTYTest < Minitest::Test
  class Kernel
    attr_reader :calls, :closed_handles, :written, :attribute_console, :command_line, :environment, :startup_attribute,
      :startup_flags, :close_started, :resize_started

    def initialize(output: ["\e[31mok".b], create_process: true, exit_code: 259, exit_code_success: true,
      close_release: nil, resize_release: nil, wait_timeouts: 1)
      @output = output.dup
      @create_process = create_process
      @exit_code = exit_code
      @exit_code_success = exit_code_success
      @calls, @closed_handles, @written = [], [], +"".b
      @process_exited, @close_started, @resize_started = Queue.new, Queue.new, Queue.new
      @close_lock, @close_ready, @close_release = Mutex.new, ConditionVariable.new, close_release
      @resize_release, @wait_timeouts = resize_release, wait_timeouts
      @process_exited << true unless exit_code == 259
      @next_handle = 10
    end

    def exit!(code = 0)
      @exit_code = code
      @process_exited << true
    end

    def fn(name, _arguments, _result, need_gvl: true)
      ->(*arguments) { invoke(name, need_gvl, arguments) }
    end

    private

    def invoke(name, need_gvl, arguments)
      @calls << [name, need_gvl]
      case name
      when :CreatePipe
        arguments[0].replace([take_handle].pack("J"))
        arguments[1].replace([take_handle].pack("J"))
        1
      when :CreatePseudoConsole
        arguments[4].replace([50].pack("J"))
        0
      when :InitializeProcThreadAttributeList
        arguments[3].replace([64].pack("J")) if arguments[0] == 0
        arguments[0] == 0 ? 0 : 1
      when :UpdateProcThreadAttribute
        @attribute_console = arguments[3]
        1
      when :CreateProcessW
        @command_line = decode(arguments[1])
        @environment = decode(arguments[6]) unless arguments[6] == 0
        @startup_flags = arguments[8].byteslice(60, 4).unpack1("I")
        @startup_attribute = arguments[8].byteslice(104, 8).unpack1("J")
        arguments[9].replace([90, 91, 1_234, 2].pack("JJII"))
        @create_process ? 1 : 0
      when :ReadFile
        bytes = @close_lock.synchronize do
          if @output.first == :after_close
            @close_ready.wait(@close_lock) until @console_closed
            @output.shift
          end
          @output.shift
        end
        return 0 unless bytes

        arguments[1][0, bytes.bytesize] = bytes
        arguments[3].replace([bytes.bytesize].pack("I"))
        1
      when :WriteFile
        @written << arguments[1]
        arguments[3].replace([arguments[2]].pack("I"))
        1
      when :GetExitCodeProcess
        arguments[1].replace([@exit_code].pack("I"))
        @exit_code_success ? 1 : 0
      when :WaitForSingleObject
        if @wait_timeouts.positive?
          @wait_timeouts -= 1
          258
        else
          @process_exited.pop
          0
        end
      when :ResizePseudoConsole
        @resize_started << true
        @resize_release&.pop
        0
      when :ClosePseudoConsole
        @close_lock.synchronize do
          @console_closed = true
          @close_ready.broadcast
        end
        @process_exited << true
        @close_started << true
        @close_release&.pop
        nil
      when :CloseHandle then @closed_handles << arguments[0]; 1
      when :DeleteProcThreadAttributeList then nil
      else raise "unexpected native call: #{name}"
      end
    end

    def take_handle
      @next_handle.tap { @next_handle += 1 }
    end

    def decode(value)
      value.force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8).delete_suffix("\0")
    end
  end

  class Backend
    attr_reader :pid, :writes, :resizes, :closes
    attr_accessor :status

    def initialize
      @pid, @writes, @resizes, @reads, @closes = 99, [], [], ["\e[32mready".b, nil], 0
    end

    def read_available(limit:) = @reads.shift&.byteslice(0, limit)
    def pending? = !@reads.empty?
    def write(bytes) = (@writes << bytes; bytes.bytesize)
    def resize(columns, rows) = @resizes << [columns, rows]
    def alive? = !status
    def close = (@closes += 1; self)
  end

  def test_facade_selects_windows_backend_and_keeps_the_public_contract
    backend = Backend.new
    arguments = nil
    factory = lambda do |**keywords|
      arguments = keywords
      backend
    end

    Gem.stub(:win_platform?, true) do
      Tarazed::Windows::ConPTY.stub(:new, factory) do
        terminal = Tarazed::PTY.new(command: "/bin/sh", cwd: Dir.pwd, columns: 40, rows: 8, env: {"A" => "B"})
        assert_nil arguments[:command]
        assert_equal 99, terminal.pid
        assert_nil terminal.reader
        assert_equal "\e[32mready", terminal.read(max_bytes: 20)
        assert_includes terminal.grid.text, "ready"
        status = Object.new
        backend.status = status
        assert_same status, terminal.status
        refute terminal.alive?
        backend.status = nil
        terminal.resize(columns: 50, rows: 10)
        terminal.key(:enter)
        terminal.signal
        assert_equal [[50, 10]], backend.resizes
        assert_equal ["\r", "\x03"], backend.writes
        refute terminal.signal("TERM")
        assert_same terminal, terminal.close
        assert_equal 2, backend.closes
      end
    end
  end

  def test_native_boundary_passes_console_pointer_and_releases_resources
    kernel = Kernel.new
    terminal = Tarazed::Windows::ConPTY.new(command: ["cmd.exe", "/c", "echo a b"], columns: 80, rows: 24,
      cwd: Dir.pwd, env: {"TARAZED_CONPTY_TEST" => "yes"}, kernel: kernel)
    terminal.instance_variable_get(:@reader).join

    assert_equal 50, kernel.attribute_console
    assert_equal 0x100, kernel.startup_flags
    assert_operator kernel.startup_attribute, :>, 0
    assert_equal 'cmd.exe /c "echo a b"', kernel.command_line
    assert_includes kernel.environment, "TARAZED_CONPTY_TEST=yes\0"
    assert_equal "\e[3", terminal.read_available(limit: 3)
    assert_equal "1mok", terminal.read_available
    assert_nil terminal.read_available
    assert_equal 3, terminal.write("abc")
    terminal.resize(100, 30)
    assert_nil terminal.status
    assert terminal.alive?
    assert_same terminal, terminal.close
    refute terminal.alive?
    assert_nil terminal.status
    assert_same terminal, terminal.close
    assert_equal "abc", kernel.written
    assert_equal [91, 10, 13, 11, 12, 90], kernel.closed_handles
    assert_equal 1, kernel.calls.count { |name, _| name == :ClosePseudoConsole }
    assert kernel.calls.any? { |name, gvl| name == :ReadFile && !gvl }
  end

  def test_natural_exit_status_is_process_status_compatible_and_cached
    terminals = [0, 7].map do |exit_code|
      kernel = Kernel.new(exit_code: exit_code)
      terminal = Tarazed::Windows::ConPTY.new(command: "cmd.exe", kernel: kernel)
      status = terminal.status

      assert status.exited?
      assert_equal exit_code, status.exitstatus
      assert_equal exit_code.zero?, status.success?
      assert_nil status.termsig
      refute terminal.alive?
      assert_same status, terminal.status
      assert_equal 1, kernel.calls.count { |name, _| name == :GetExitCodeProcess }
      terminal
    end
  ensure
    terminals&.each(&:close)
  end

  def test_natural_exit_closes_once_while_the_reader_drains_final_output
    release = Queue.new
    kernel = Kernel.new(output: [:after_close, "late".b], exit_code: 0, close_release: release)
    terminal = Tarazed::Windows::ConPTY.new(command: "cmd.exe", kernel: kernel)
    wait_until { !kernel.close_started.empty? }
    kernel.close_started.pop
    closer = Thread.new { terminal.close }
    wait_until { terminal.instance_variable_get(:@closed) }
    release << true
    assert closer.join(1), "close did not finish"

    assert_equal "late", terminal.read_available
    assert_nil terminal.read_available
    assert_same terminal, terminal.close
    assert_equal 1, kernel.calls.count { |name, _| name == :ClosePseudoConsole }
    assert kernel.calls.any? { |name, gvl| name == :WaitForSingleObject && !gvl }
  ensure
    release << true if release
    closer&.join(1)
    terminal&.close
  end

  def test_resize_finishes_before_natural_release_and_is_ignored_afterward
    resize_release = Queue.new
    kernel = Kernel.new(resize_release: resize_release)
    terminal = Tarazed::Windows::ConPTY.new(command: "cmd.exe", kernel: kernel)
    resizer = Thread.new { terminal.resize(100, 30) }
    wait_until { !kernel.resize_started.empty? }
    kernel.resize_started.pop
    kernel.exit!
    resize_release << true
    assert resizer.join(1), "resize did not finish"
    wait_until { kernel.calls.any? { |name, _| name == :ClosePseudoConsole } }

    assert_nil terminal.resize(120, 40)
    assert_equal 1, kernel.calls.count { |name, _| name == :ResizePseudoConsole }
  ensure
    resize_release << true if resize_release
    resizer&.join(1)
    terminal&.close
  end

  def test_concurrent_close_wakes_a_waiting_watcher_and_owns_each_handle_once
    kernel = Kernel.new
    terminal = Tarazed::Windows::ConPTY.new(command: "cmd.exe", kernel: kernel)
    wait_until { kernel.calls.count { |name, _| name == :WaitForSingleObject } >= 2 }
    closers = 2.times.map { Thread.new { terminal.close } }
    closers.each { |thread| assert thread.join(1), "close did not finish" }

    assert_equal 1, kernel.calls.count { |name, _| name == :ClosePseudoConsole }
    assert_equal [91, 10, 13, 11, 12, 90], kernel.closed_handles
    assert_equal kernel.closed_handles, kernel.closed_handles.uniq
  ensure
    closers&.each { |thread| thread.join(1) }
    terminal&.close
  end

  def test_exit_status_api_failure_does_not_prevent_close
    kernel = Kernel.new(exit_code_success: false)
    terminal = Tarazed::Windows::ConPTY.new(command: "cmd.exe", kernel: kernel)

    assert_raises(SystemCallError) { terminal.status }
    assert_same terminal, terminal.close
    assert_nil terminal.status
    assert_equal [91, 10, 13, 11, 12, 90], kernel.closed_handles
  end

  def test_failed_process_creation_releases_every_owned_handle
    kernel = Kernel.new(create_process: false)

    assert_raises(SystemCallError) do
      Tarazed::Windows::ConPTY.new(command: "cmd.exe", kernel: kernel)
    end
    assert_equal [11, 12, 10, 13], kernel.closed_handles
    assert_equal 1, kernel.calls.count { |name, _| name == :ClosePseudoConsole }
    assert_equal 1, kernel.calls.count { |name, _| name == :DeleteProcThreadAttributeList }
  end

  def test_string_command_remains_a_complete_windows_command_line
    kernel = Kernel.new
    terminal = Tarazed::Windows::ConPTY.new(command: "cmd.exe /c echo ready", kernel: kernel)

    assert_equal "cmd.exe /c echo ready", kernel.command_line
  ensure
    terminal&.close
  end

  def test_windows_argument_quoting_matches_the_crt_contract
    quote = Tarazed::Windows::ConPTY.method(:quote_argument)

    assert_equal "plain", quote.call("plain")
    assert_equal '""', quote.call("")
    assert_equal '"a b"', quote.call("a b")
    assert_equal '"a\\\\\\"b"', quote.call('a\\"b')
    assert_equal '"a b\\\\"', quote.call("a b\\")
  end

  private

  def wait_until
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
    until yield
      flunk "condition was not met" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.001
    end
  end
end
