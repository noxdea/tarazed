# frozen_string_literal: true

require "fiddle"

module Tarazed
  module Windows
    class Library
      def initialize(name)
        @handle = Fiddle.dlopen(name)
        @functions = {}
      end

      def fn(name, arguments, result, need_gvl: true)
        @functions[[name, arguments, result, need_gvl]] ||= Fiddle::Function.new(
          @handle[name.to_s], arguments, result, name: name.to_s, need_gvl: need_gvl
        )
      end
    end

    # Windows ConPTY backend. PTY owns the shared grid and VT parser.
    class ConPTY
      P, I, U, N, V = Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_UINT, Fiddle::TYPE_SIZE_T,
        Fiddle::TYPE_VOID
      private_constant :P, :I, :U, :N, :V

      attr_reader :pid

      def initialize(command: nil, columns: 80, rows: 24, cwd: nil, env: {}, kernel: nil)
        raise Error, "ConPTY requires 64-bit Windows Ruby" unless Fiddle::SIZEOF_VOIDP == 8

        @kernel = kernel || Library.new("kernel32.dll")
        @output, @pending, @closed, @eof = Queue.new, +"".b, false, false
        input_read, @input_write = pipe
        @output_read, output_write = pipe
        console = [0].pack("J")
        check_hresult(function(:CreatePseudoConsole, [I, P, P, U, P], I).call(
          coordinate(columns, rows), input_read, output_write, 0, console
        ))
        @console = console.unpack1("J")
        attributes = process_attributes(@console)
        @process, @pid = spawn(command, cwd, env, attributes)
        start_reader
      rescue Fiddle::DLError, LoadError => error
        release
        raise Error, "ConPTY is unavailable: #{error.message}"
      rescue
        release
        raise
      ensure
        begin
          function(:DeleteProcThreadAttributeList, [P], V).call(attributes) if attributes
        rescue StandardError
          nil
        end
        close_handle(input_read)
        close_handle(output_write)
      end

      # CommandLineToArgvW/CRT escaping.
      def self.quote_argument(value)
        return value unless value.empty? || value.match?(/[\s"]/)

        '"' + value.gsub(/(\\*)"/) { Regexp.last_match(1) * 2 + '\\"' }
          .sub(/(\\+)\z/) { Regexp.last_match(1) * 2 } + '"'
      end

      def read_available(limit: 65_536)
        raise ArgumentError, "limit must be positive" unless limit.is_a?(Integer) && limit.positive?

        until @output.empty?
          bytes = @output.pop
          if bytes.nil?
            @eof = true
            break
          end
          @pending << bytes
        end
        return nil if @pending.empty? && @eof

        @pending.slice!(0, limit)
      end

      def pending? = !@pending.empty? || !@output.empty?

      def write(bytes)
        raise IOError, "terminal closed" if @closed

        offset = 0
        while offset < bytes.bytesize
          chunk = bytes.byteslice(offset, bytes.bytesize - offset)
          count = [0].pack("I")
          check(function(:WriteFile, [P, P, U, P, P], I, need_gvl: false).call(
            @input_write, chunk, chunk.bytesize, count, 0
          ), "WriteFile")
          written = count.unpack1("I")
          raise IOError, "ConPTY write made no progress" if written.zero?

          offset += written
        end
        offset
      end

      def resize(columns, rows)
        check_hresult(function(:ResizePseudoConsole, [P, I], I).call(@console, coordinate(columns, rows)))
      end

      def alive?
        !@closed && function(:WaitForSingleObject, [P, U], U).call(@process, 0) == 258
      end

      def close
        return self if @closed

        @closed = true
        close_handle(@input_write)
        @input_write = nil
        close_console
        @reader&.join(2)
        close_handle(@output_read)
        close_handle(@process)
        @output_read = @process = nil
        self
      end

      private

      def function(name, arguments, result, need_gvl: true)
        @kernel.fn(name, arguments, result, need_gvl: need_gvl)
      end

      def process_attributes(console)
        size = [0].pack("J")
        function(:InitializeProcThreadAttributeList, [P, U, U, P], I).call(0, 1, 0, size)
        attributes = Fiddle::Pointer.malloc(size.unpack1("J"), Fiddle::RUBY_FREE)
        check(function(:InitializeProcThreadAttributeList, [P, U, U, P], I).call(
          attributes, 1, 0, size
        ), "InitializeProcThreadAttributeList")
        check(function(:UpdateProcThreadAttribute, [P, U, N, P, N, P, P], I).call(
          attributes, 0, 0x20016, console, Fiddle::SIZEOF_VOIDP, 0, 0
        ), "UpdateProcThreadAttribute")
        attributes
      rescue
        safely { function(:DeleteProcThreadAttributeList, [P], V).call(attributes) } if attributes
        raise
      end

      def spawn(command, cwd, env, attributes)
        startup = "\0".b * 112
        startup[0, 4] = [112].pack("I")
        startup[60, 4] = [0x100].pack("I") # STARTF_USESTDHANDLES
        startup[104, 8] = [attributes.to_i].pack("J")
        info = "\0".b * 24
        command ||= ENV.fetch("COMSPEC", "cmd.exe")
        raise ArgumentError, "terminal command required" if command.respond_to?(:empty?) && command.empty?

        line = if command.is_a?(Array)
          command.map { |part| self.class.quote_argument(part.to_s) }.join(" ")
        else
          command.to_s
        end
        line = wide(line)
        directory = cwd ? wide(File.expand_path(cwd)) : nil
        environment = environment_block(env)
        check(function(:CreateProcessW, [P, P, P, P, I, U, P, P, P, P], I).call(
          0, line, 0, 0, 0, 0x00080400, environment || 0, directory || 0, startup, info
        ), "CreateProcessW")
        process, thread, pid = info.unpack("JJI")
        close_handle(thread)
        [process, pid]
      end

      def environment_block(overrides)
        return if overrides.empty?

        environment = ENV.to_h
        overrides.each do |key, value|
          key = key.to_s
          value.nil? ? environment.delete(key) : environment[key] = value.to_s
        end
        (environment.sort_by { |key, _| key.downcase }.map { |key, value| "#{key}=#{value}\0" }.join + "\0")
          .encode("UTF-16LE").b
      end

      def wide(text) = text.encode("UTF-16LE").b + "\0\0"

      def coordinate(columns, rows)
        unless columns.is_a?(Integer) && rows.is_a?(Integer) && columns.between?(1, 32_767) && rows.between?(1, 32_767)
          raise ArgumentError, "invalid terminal size"
        end

        [columns, rows].pack("s2").unpack1("l")
      end

      def pipe
        read_handle, write_handle = [0].pack("J"), [0].pack("J")
        check(function(:CreatePipe, [P, P, P, U], I).call(read_handle, write_handle, 0, 0), "CreatePipe")
        [read_handle.unpack1("J"), write_handle.unpack1("J")]
      end

      def start_reader
        @reader = Thread.new do
          loop do
            bytes, count = "\0".b * 65_536, [0].pack("I")
            ok = function(:ReadFile, [P, P, U, P, P], I, need_gvl: false).call(
              @output_read, bytes, bytes.bytesize, count, 0
            )
            break if ok.zero? || count.unpack1("I").zero?

            @output << bytes.byteslice(0, count.unpack1("I"))
          end
        ensure
          @output << nil
        end
      end

      def close_console
        return unless @console

        function(:ClosePseudoConsole, [P], V, need_gvl: false).call(@console)
        @console = nil
      end

      def release
        safely { close_handle(@input_write) }
        safely { close_console }
        @reader&.join(2)
        safely { close_handle(@output_read) }
        safely { close_handle(@process) }
        @input_write = @output_read = @process = nil
      end

      def safely
        yield
      rescue StandardError
        nil
      end

      def close_handle(handle)
        function(:CloseHandle, [P], I).call(handle) if handle && !handle.zero?
      end

      def check(result, name)
        raise SystemCallError.new(name, Fiddle.last_error) if result.zero?

        result
      end

      def check_hresult(result)
        raise Error, "ConPTY failure 0x#{(result & 0xffffffff).to_s(16)}" unless (result & 0x80000000).zero?

        result
      end
    end
  end
end
