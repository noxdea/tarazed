# frozen_string_literal: true

module Tarazed
  class Scrollback
    include Enumerable

    attr_reader :limit

    def initialize(limit)
      raise ArgumentError, "scrollback limit must be nonnegative" unless limit.is_a?(Integer) && limit >= 0

      @limit = limit
      clear
    end

    def clear = @rows = []
    def length = @rows.length
    alias size length
    def [](index) = @rows[index]
    def each(&block) = block ? @rows.each(&block) : enum_for(__method__)

    def push(cells)
      return if limit.zero?

      @rows.shift if @rows.length == limit
      @rows << cells.map { |cell| cell.dup.tap { |copy| copy.text = copy.text.dup.freeze }.freeze }.freeze
    end
  end
end
