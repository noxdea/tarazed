# frozen_string_literal: true

require_relative "tarazed/version"
require_relative "tarazed/cell"
require_relative "tarazed/scrollback"
require_relative "tarazed/grid"
require_relative "tarazed/vt"
require_relative "tarazed/pty"

module Tarazed
  class Error < StandardError; end

  module Value
    module_function

    def define(*members)
      return Data.define(*members) if defined?(Data)

      Struct.new(*members) do
        members.each { |member| undef_method("#{member}=") }

        def initialize(*values, **keywords)
          if keywords.empty?
            raise ArgumentError, "wrong number of arguments" unless values.length == self.class.members.length

            super(*values)
          else
            raise ArgumentError, "cannot mix positional and keyword arguments" unless values.empty?

            missing = self.class.members - keywords.keys
            unknown = keywords.keys - self.class.members
            raise ArgumentError, "missing keyword: #{missing.first.inspect}" unless missing.empty?
            raise ArgumentError, "unknown keyword: #{unknown.first.inspect}" unless unknown.empty?

            super(*self.class.members.map { |member| keywords.fetch(member) })
          end
          freeze
        end

        def with(**changes)
          return self if changes.empty?

          unknown = changes.keys - self.class.members
          raise ArgumentError, "unknown keyword: #{unknown.first.inspect}" unless unknown.empty?

          self.class.new(**to_h.merge(changes))
        end
      end
    end
  end

  Command = Value.define(:id, :prompt_row, :input, :output_range, :exit_status, :started_at, :finished_at, :cwd)
  private_constant :Value
end

require_relative "tarazed/shell_integration"
require_relative "tarazed/session"
