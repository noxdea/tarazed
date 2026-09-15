# frozen_string_literal: true

module Tarazed
  class Scrollback
    include Enumerable

    attr_reader :limit, :total

    def initialize(limit)
      raise ArgumentError, "scrollback limit must be nonnegative" unless limit.is_a?(Integer) && limit >= 0

      @limit = limit
      @total = 0
      clear
    end

    def clear = @rows = []
    def length = @rows.length
    alias size length
    def [](index) = @rows[index]
    def each(&block) = block ? @rows.each(&block) : enum_for(__method__)

    def push(cells)
      advance(1)
      return if limit.zero?

      @rows.shift if @rows.length == limit
      row = cells.map { |cell| cell.dup.tap { |copy| copy.text = copy.text.dup.freeze }.freeze }
      row.instance_variable_set(:@wrapped, true) if cells.instance_variable_get(:@wrapped)
      @rows << row.freeze
    end

    def advance(count) = @total += count
  end
end
