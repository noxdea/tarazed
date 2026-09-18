# frozen_string_literal: true

module Tarazed
  class Session < PTY
    def initialize(command:, env: {}, cwd: Dir.pwd, columns: 80, rows: 24, scrollback_limit: 10_000,
      command_history_limit: 1_000, queue_limit_bytes: 8_388_608, on_command: nil)
      super(command: command, env: env, cwd: cwd, columns: columns, rows: rows, scrollback: scrollback_limit,
        command_history_limit: command_history_limit, queue_limit_bytes: queue_limit_bytes, on_command: on_command)
    end

    def screen = grid
    def commands = vt.commands
    def clear_commands
      vt.clear_commands
      self
    end
    def cwd = vt.cwd || initial_cwd
    def input(bytes) = write(bytes)

    def pump(timeout: 0)
      bytes = read(timeout: timeout)
      !bytes.nil? && !bytes.empty?
    end
  end
end
