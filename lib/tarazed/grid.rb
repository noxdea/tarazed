# frozen_string_literal: true

require "unicode/display_width"

module Tarazed
  class Grid
    attr_reader :columns, :rows, :cells, :scrollback, :cursor_x, :cursor_y, :scroll_top, :scroll_bottom
    attr_accessor :foreground, :background, :attributes, :hyperlink, :autowrap, :insert_mode, :origin_mode,
      :cursor_visible

    def initialize(columns: 80, rows: 24, scrollback: 10_000)
      validate_dimensions(columns, rows)
      @columns, @rows = columns, rows
      @scrollback = Scrollback.new(scrollback)
      reset
    end

    def reset
      @foreground = @background = @hyperlink = nil
      @attributes = {}.freeze
      @autowrap = @cursor_visible = true
      @insert_mode = @origin_mode = false
      @cursor_x = @cursor_y = 0
      @wrap_pending = false
      @alternate = nil
      @scroll_top, @scroll_bottom = 0, rows - 1
      @cells = Array.new(rows) { blank_row }
      @tabs = (8...columns).step(8).to_a
      save_cursor
    end

    def [](row, column = nil) = column ? cells[row]&.[](column) : cells[row]
    def alternate? = !@alternate.nil?
    def lines = cells.map { |row| row.map(&:text).join.rstrip }
    def text = lines.join("\n")
    def history_row = scrollback.total + cursor_y
    def wrap_pending? = @wrap_pending

    def put(char)
      width = self.class.width(char)
      previous_x = @wrap_pending ? cursor_x : cursor_x - 1
      if previous_x >= 0 && !char.ascii_only?
        previous_x -= 1 if cells[cursor_y][previous_x].width.zero? && previous_x.positive?
        previous = cells[cursor_y][previous_x]
        joined = previous.text + char
        if joined.match?(/\A\X\z/)
          width = [self.class.width(joined), columns].min
          if previous_x + width > columns && autowrap
            cells[cursor_y][previous_x] = blank
            mark_wrapped(cells[cursor_y])
            carriage_return
            linefeed
            return put(joined)
          end
          width = [width, columns - previous_x].min
          clear_wide(cursor_y, previous_x + 1) if width == 2 && previous.width < 2
          cells[cursor_y][previous_x + 1] = blank if width < previous.width
          previous.text, previous.width = joined, width
          if width == 2
            cells[cursor_y][previous_x + 1] = previous.dup.tap { |cell| cell.text = ""; cell.width = 0 }
          end
          @cursor_x = [previous_x + width, columns - 1].min
          @wrap_pending = previous_x + width >= columns && autowrap
          return
        end
      end
      return if width.zero?

      width = 1 if width > columns
      if @wrap_pending || (width == 2 && cursor_x == columns - 1)
        if autowrap
          mark_wrapped(cells[cursor_y])
          @cursor_x = 0
          linefeed
        elsif width == 2
          return
        end
        @wrap_pending = false
      end
      insert_characters(width) if insert_mode
      clear_wide(cursor_y, cursor_x)
      clear_wide(cursor_y, cursor_x + 1) if width == 2
      cells[cursor_y][cursor_x] = Cell.new(text: char, width: width, foreground: foreground,
        background: background, attributes: attributes, hyperlink: hyperlink)
      if width == 2
        cells[cursor_y][cursor_x + 1] = Cell.new(text: "", width: 0, foreground: foreground,
          background: background, attributes: attributes, hyperlink: hyperlink)
      end
      if cursor_x + width >= columns
        @cursor_x = columns - 1
        @wrap_pending = autowrap
      else
        @cursor_x += width
      end
    end

    # Internal parser fast path; callers normally use VT#feed.
    def put_ascii(text)
      capacity = columns * rows
      if text.bytesize >= capacity && scrollback.limit.zero? && pristine_default_screen?
        complete_rows, remainder = text.bytesize.divmod(columns)
        retained_complete_rows = remainder.zero? ? rows : rows - 1
        start = (complete_rows - retained_complete_rows) * columns
        visible = text.byteslice(start..).dup.force_encoding(Encoding::UTF_8)
        @cells = visible.each_char.each_slice(columns).map do |characters|
          row = characters.map do |char|
            Cell.new(text: char, width: 1, foreground: nil, background: nil, attributes: @attributes, hyperlink: nil)
          end
          row.concat(Array.new(columns - row.length) { blank })
        end
        @cells.each_with_index { |row, index| mark_wrapped(row) if index < @cells.length - 1 }
        scrollback.advance(complete_rows - retained_complete_rows)
        @cursor_x = remainder.zero? ? columns - 1 : remainder
        @cursor_y = rows - 1
        @wrap_pending = remainder.zero?
      else
        text.each_byte { |byte| put(byte.chr) }
      end
    end

    def self.width(char)
      return 1 if char.bytesize == 1 && char.ord.between?(32, 126)

      Unicode::DisplayWidth.of(char, ambiguous: 1, emoji: :rgi)
    end

    def move(x: cursor_x, y: cursor_y, relative: false)
      if relative
        x += cursor_x
        y += cursor_y
      end
      top, bottom = origin_mode ? [scroll_top, scroll_bottom] : [0, rows - 1]
      @cursor_x = x.clamp(0, columns - 1)
      @cursor_y = y.clamp(top, bottom)
      @wrap_pending = false
    end

    def position(row, column)
      move(x: column - 1, y: row - 1 + (origin_mode ? scroll_top : 0))
    end

    def carriage_return = move(x: 0)
    def backspace = move(x: cursor_x - 1)

    def linefeed
      @wrap_pending = false
      if cursor_y == scroll_bottom
        scroll_up
      elsif cursor_y < rows - 1
        @cursor_y += 1
      end
    end

    def reverse_index
      @wrap_pending = false
      cursor_y == scroll_top ? scroll_down : @cursor_y = [0, cursor_y - 1].max
    end

    def tab(count = 1, backward: false)
      count.times do
        stop = if backward
          @tabs.reverse.find { |column| column < cursor_x }
        else
          @tabs.find { |column| column > cursor_x }
        end
        move(x: stop || (backward ? 0 : columns - 1))
      end
    end

    def tab_set = @tabs = (@tabs + [cursor_x]).uniq.sort
    def tab_clear(all: false) = all ? @tabs.clear : @tabs.delete(cursor_x)

    def margins(top = 1, bottom = rows)
      return unless top >= 1 && top < bottom && bottom <= rows

      @scroll_top, @scroll_bottom = top - 1, bottom - 1
      position(1, 1)
    end

    def scroll_up(count = 1)
      [count, scroll_bottom - scroll_top + 1].min.times do
        removed = cells.delete_at(scroll_top)
        scrollback.push(removed) if scroll_top.zero? && scroll_bottom == rows - 1 && !alternate?
        cells.insert(scroll_bottom, blank_row)
      end
    end

    def scroll_down(count = 1)
      [count, scroll_bottom - scroll_top + 1].min.times do
        cells.delete_at(scroll_bottom)
        cells.insert(scroll_top, blank_row)
      end
    end

    def erase_display(mode = 0)
      case mode
      when 0
        erase_line(0)
        ((cursor_y + 1)...rows).each { |row| cells[row] = blank_row }
      when 1
        (0...cursor_y).each { |row| cells[row] = blank_row }
        erase_line(1)
      when 2 then @cells = Array.new(rows) { blank_row }
      when 3 then scrollback.clear
      end
    end

    def erase_line(mode = 0)
      first, last = case mode
      when 0 then [cursor_x, columns - 1]
      when 1 then [0, cursor_x]
      when 2 then [0, columns - 1]
      else return
      end
      (first..last).each do |column|
        clear_wide(cursor_y, column)
        cells[cursor_y][column] = blank
      end
    end

    def erase_characters(count = 1)
      (cursor_x...[cursor_x + count, columns].min).each do |column|
        clear_wide(cursor_y, column)
        cells[cursor_y][column] = blank
      end
    end

    def insert_characters(count = 1)
      clear_wide(cursor_y, cursor_x) if cells[cursor_y][cursor_x].width.zero?
      cells[cursor_y].insert(cursor_x, *Array.new([count, columns - cursor_x].min) { blank })
      cells[cursor_y] = cells[cursor_y].first(columns)
      normalize_row(cursor_y)
    end

    def delete_characters(count = 1)
      clear_wide(cursor_y, cursor_x)
      count = [count, columns - cursor_x].min
      cells[cursor_y].slice!(cursor_x, count)
      cells[cursor_y].concat(Array.new(count) { blank })
      normalize_row(cursor_y)
    end

    def insert_lines(count = 1)
      return unless cursor_y.between?(scroll_top, scroll_bottom)

      [count, scroll_bottom - cursor_y + 1].min.times do
        cells.delete_at(scroll_bottom)
        cells.insert(cursor_y, blank_row)
      end
    end

    def delete_lines(count = 1)
      return unless cursor_y.between?(scroll_top, scroll_bottom)

      [count, scroll_bottom - cursor_y + 1].min.times do
        cells.delete_at(cursor_y)
        cells.insert(scroll_bottom, blank_row)
      end
    end

    def save_cursor
      @saved = [cursor_x, cursor_y, foreground, background, attributes, hyperlink, origin_mode, @wrap_pending]
    end

    def restore_cursor
      return unless @saved

      @cursor_x, @cursor_y, @foreground, @background, @attributes, @hyperlink, @origin_mode, @wrap_pending = @saved
      @cursor_x = cursor_x.clamp(0, columns - 1)
      @cursor_y = cursor_y.clamp(0, rows - 1)
    end

    def alternate(enable, save: true)
      if enable && !alternate?
        save_cursor if save
        @alternate = cells
        @cells = Array.new(rows) { blank_row }
        @cursor_x = @cursor_y = 0
        @scroll_top, @scroll_bottom = 0, rows - 1
        @wrap_pending = false
      elsif !enable && alternate?
        @cells, @alternate = @alternate, nil
        @scroll_top, @scroll_bottom = 0, rows - 1
        restore_cursor if save
      end
    end

    def resize(columns:, rows:)
      validate_dimensions(columns, rows)
      previous_columns = @columns
      @columns, @rows = columns, rows
      primary = alternate? ? @alternate : cells
      [cells, @alternate].compact.each do |screen|
        while screen.length > rows
          removed = screen.shift
          scrollback.push(removed) if screen.equal?(primary)
          @cursor_y -= 1 if screen.equal?(cells)
        end
        screen << blank_row while screen.length < rows
        screen.each do |row|
          row.slice!(columns, row.length) if row.length > columns
          row << blank while row.length < columns
        end
      end
      cells.each_index { |index| normalize_row(index) }
      added_tabs = (previous_columns...columns).select { |column| column.positive? && (column % 8).zero? }
      @tabs = (@tabs.select { |column| column < columns } + added_tabs).uniq.sort
      @scroll_top, @scroll_bottom = 0, rows - 1
      move
    end

    # Coordinates are [column, row]; finish is exclusive, including scrollback
    # when history: true. This is suitable for selection/copy without a renderer.
    def selection(start, finish, history: false)
      source = history ? scrollback.to_a + cells : cells
      start, finish = finish, start if ([start[1], start[0]] <=> [finish[1], finish[0]]) == 1
      parts = (start[1]..finish[1]).map do |row|
        next ["", false] unless source[row]

        first = row == start[1] ? start[0] : 0
        last = row == finish[1] ? finish[0] : columns
        [source[row][first...last].to_a.map(&:text).join.rstrip, source[row].instance_variable_get(:@wrapped)]
      end
      parts.each_with_index.each_with_object(+"") do |((part, _), index), text|
        text << "\n" if index.positive? && !parts[index - 1][1]
        text << part
      end
    end

    def links(row)
      line = cells.fetch(row).map(&:text).join
      explicit = []
      cells[row].each_with_index do |cell, column|
        next unless cell.hyperlink

        if explicit.last && explicit.last[:url] == cell.hyperlink && explicit.last[:end_column] == column
          explicit.last[:end_column] = column + 1
        else
          explicit << {url: cell.hyperlink, column: column, end_column: column + 1}
        end
      end
      line.to_enum(:scan, %r{https?://[^\s<>"']+}).each do
        found = Regexp.last_match
        column = line[0...found.begin(0)].each_char.sum { |char| self.class.width(char) }
        explicit << {url: found[0], column: column, end_column: column + found[0].length}
      end
      explicit.uniq
    end

    def file_paths(row, cwd: Dir.pwd)
      line = cells.fetch(row).map(&:text).join
      line.scan(%r{(?:\A|[\s("'])([^\s:"'()]+):(\d+)(?::(\d+))?}).filter_map do |name, number, column|
        absolute = File.expand_path(name, cwd)
        {path: absolute, line: number.to_i, column: column ? column.to_i : 1} if File.file?(absolute)
      end
    end

    private

    def validate_dimensions(columns, rows)
      return if columns.is_a?(Integer) && rows.is_a?(Integer) && columns.positive? && rows.positive?

      raise ArgumentError, "terminal dimensions must be positive integers"
    end

    def pristine_default_screen?
      cursor_x.zero? && cursor_y.zero? && !@wrap_pending && !alternate? && foreground.nil? && background.nil? &&
        hyperlink.nil? && attributes.empty? && cells.all? { |row| row.all? { |cell| cell.text == " " && cell.width == 1 } }
    end

    def blank = Cell.new(text: " ", width: 1, foreground: foreground, background: background, attributes: {}.freeze)
    def blank_row = Array.new(columns) { blank }
    def mark_wrapped(row) = row.instance_variable_set(:@wrapped, true)

    def clear_wide(row, column)
      return unless column.between?(0, columns - 1)

      cell = cells[row][column]
      cells[row][column - 1] = blank if cell.width.zero? && column.positive?
      cells[row][column + 1] = blank if cell.width == 2 && column + 1 < columns
    end

    def normalize_row(row)
      cells[row].each_with_index do |cell, column|
        invalid_lead = cell.width == 2 && (column == columns - 1 || cells[row][column + 1].width != 0)
        invalid_tail = cell.width.zero? && (column.zero? || cells[row][column - 1].width != 2)
        cells[row][column] = blank if invalid_lead || invalid_tail
      end
    end
  end
end
