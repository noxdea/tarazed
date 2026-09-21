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

    def search(query, regex: false, normalize: true, rows: @rows)
      matcher = regex ? Regexp.new(query.to_s) : query.to_s
      rows.each_with_index.filter_map do |cells, index|
        text = cells.map(&:text).join.rstrip
        comparable = normalize && text.respond_to?(:unicode_normalize) ? text.unicode_normalize(:nfc) : text
        match = regex ? matcher.match(comparable) : comparable.index(matcher)
        next unless match

        range = if match.is_a?(MatchData)
          match.begin(0)...match.end(0)
        else
          match...(match + matcher.length)
        end
        {index: index, text: text, range: range}.freeze
      end.freeze
    rescue RegexpError => error
      raise ArgumentError, "invalid search pattern: #{error.message}"
    end

    def advance(count) = @total += count
  end
end
