# frozen_string_literal: true

require_relative "test_helper"

class PTYTest < Minitest::Test
  def test_real_process_input_resize_and_cleanup
    child = <<~'RUBY'
      require "io/console"
      STDIN.binmode
      STDOUT.binmode
      STDOUT.sync = true
      STDOUT.write("\e[32mready\e[0m\r\n")
      answer = STDIN.gets.chomp
      STDOUT.write("reply:#{answer}\r\n#{STDOUT.winsize.join(' ')}\r\n")
    RUBY
    terminal = Tarazed::PTY.new(command: [RbConfig.ruby, "-e", child], columns: 40, rows: 8)
    output = +""
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until output.include?("ready")
      raise "PTY did not start" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      output << terminal.read(timeout: 0.1).to_s
    end
    terminal.resize(columns: 50, rows: 10)
    terminal.write("hello\r")
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      chunk = terminal.read(timeout: 0.1)
      break unless chunk

      output << chunk
    end
    assert_includes output, "reply:hello"
    assert_includes output, "10 50"
    assert_includes terminal.grid.text, "ready"
    ready_row = terminal.grid.lines.index("ready")
    assert_equal 2, terminal.grid[ready_row, 0].foreground
    terminal.close
    refute terminal.alive?
  ensure
    terminal&.close
  end

  def test_reader_queue_applies_backpressure_without_losing_output
    skip "uses the POSIX reader queue" if Gem.win_platform?

    size = 100_000
    terminal = Tarazed::PTY.new(command: [RbConfig.ruby, "-e", "STDOUT.write(\"\\0\" * #{size})"],
      queue_limit_bytes: 65_536)
    total = 0
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    while total < size
      chunk = terminal.read(timeout: 0.05, max_bytes: 32_768, max_seconds: 0.004)
      break unless chunk

      total += chunk.count("\0")
      raise "PTY output timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    end
    assert_equal size, total
  ensure
    terminal&.close
  end

  def test_validates_read_and_queue_limits
    assert_raises(ArgumentError) { Tarazed::PTY.new(command: [RbConfig.ruby, "-e", ""], queue_limit_bytes: 0) }
    skip "uses a POSIX child command" if Gem.win_platform?

    terminal = Tarazed::PTY.new(command: [RbConfig.ruby, "-e", "sleep 0.1"])
    assert_raises(ArgumentError) { terminal.read(max_bytes: 0) }
    assert_raises(ArgumentError) { terminal.read(timeout: -1) }
    assert_raises(ArgumentError) { terminal.read(max_seconds: -1) }
  ensure
    terminal&.close
  end

  def test_signal_falls_back_to_the_child_when_its_process_group_is_unavailable
    terminal = Tarazed::PTY.allocate
    terminal.instance_variable_set(:@pid, 123)
    targets = []
    killer = lambda do |_name, target|
      targets << target
      raise Errno::EPERM if target.negative?

      1
    end

    assert_equal 1, Process.stub(:kill, killer) { terminal.signal }
    assert_equal [-123, 123], targets
  end
end
