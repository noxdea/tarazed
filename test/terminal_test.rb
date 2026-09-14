# frozen_string_literal: true

require_relative "test_helper"

class TerminalTest < Minitest::Test
  def setup
    @grid = Tarazed::Grid.new(columns: 12, rows: 4, scrollback: 3)
    @vt = Tarazed::VT.new(@grid)
  end

  def test_alternate_screen_attributes_osc_and_replies
    @vt.feed("main\e[?1049h\e[1;3;4;91;48;5;123mA\e[38:2::12:34:56mB")
    assert @grid.alternate?
    assert_equal 9, @grid[0, 0].foreground
    assert_equal 123, @grid[0, 0].background
    assert_equal({bold: true, italic: true, underline: 1}, @grid[0, 0].attributes)
    assert_equal [12, 34, 56], @grid[0, 1].foreground
    @vt.feed("\e]8;;https://example.invalid\e\\link\e]8;;\a\e]7;file:///tmp/a%20b\a\e]2;日本語\a\e[6n")
    assert_equal "/tmp/a b", @vt.cwd
    assert_equal "日本語", @vt.title
    assert_equal "https://example.invalid", @grid[0, 2].hyperlink
    assert_equal ["\e[1;7R"], @vt.replies
    @vt.feed("\e[?1049l")
    assert_equal "main", @grid.lines.first
    assert_equal [4, 0], [@grid.cursor_x, @grid.cursor_y]
    assert_nil @grid.foreground
  end

  def test_margins_editing_tabs_graphics_and_dcs
    @vt.feed("one\r\ntwo\r\nthree\r\nfour\e[2;3r\e[3;1H\n")
    assert_equal ["one", "three", "", "four"], @grid.lines
    assert_equal 0, @grid.scrollback.length
    @vt.feed("\e[r\e[H\e[2Kabcdef\e[1;3H\e[2P\e[2@XY")
    assert_equal "abXYef", @grid.lines[0]
    @vt.feed("\e[2;1H\e[2K\e(0lqk\e(B\t!")
    assert_equal "┌─┐     !", @grid.lines[1]
    @vt.feed("\eP$qm\e\\")
    assert_equal "\eP1$r0m\e\\", @vt.replies.last
    @vt.feed("\ePignored payload\e\\ok")
    assert_includes @grid.text, "ok"
  end

  def test_input_mouse_bracketed_paste_and_selection
    assert_equal "\e[A", @vt.key(:up)
    @vt.feed("\e[?1h\e[?2004h\e[?1002h\e[?1006h")
    assert_equal "\eOA", @vt.key(:up)
    assert_equal "\e[1;5D", @vt.key(:left, control: true)
    assert_equal "\x03", @vt.key("c", control: true)
    assert_equal "\e[200~hello\n\e[201~", @vt.paste("hello\n")
    assert_equal "\e[<0;3;4M", @vt.mouse(button: :left, column: 2, row: 3)
    assert_equal "\e[<0;3;4m", @vt.mouse(button: :left, column: 2, row: 3, action: :release)
    assert_equal "", @vt.mouse(button: nil, column: 2, row: 3, action: :move)
    @vt.feed("hello\r\nworld")
    assert_equal "ello\nwor", @grid.selection([1, 0], [3, 1])
    assert_equal "ello\nwor", @grid.selection([3, 1], [1, 0])
  end

  def test_resize_normalizes_wide_cells_and_limits_history
    @vt.feed("1234567890日")
    @grid.resize(columns: 11, rows: 4)
    assert_equal 1, @grid[0, 10].width
    10.times { @vt.feed("\r\nline") }
    assert_equal 3, @grid.scrollback.length
    @grid.resize(columns: 20, rows: 2)
    assert_equal 2, @grid.cells.length
    assert @grid.cells.all? { |row| row.length == 20 }
    assert @grid.cursor_y.between?(0, 1)
  end

  def test_modes_line_operations_replies_and_bell
    @vt.feed("abc\e7\e[4h\e[2GZ\e[4l\e8\a\e[5n\e[c\e[18t")
    assert_equal "aZbc", @grid.lines.first
    assert_equal 1, @vt.bell_count
    assert_equal ["\e[0n", "\e[?1;2c", "\e[8;4;12t"], @vt.replies
    @vt.feed("\e[2;4r\e[2;1H\e[Lx\e[M\e[S\e[T")
    assert_equal [1, 3], [@grid.scroll_top, @grid.scroll_bottom]
  end

  def test_explicit_and_detected_links_and_file_positions
    grid = Tarazed::Grid.new(columns: 80, rows: 2)
    vt = Tarazed::VT.new(grid)
    vt.feed("\e]8;;https://example.com/a\e\\go\e]8;;\e\\ https://ruby-lang.org/")
    assert_equal({url: "https://example.com/a", column: 0, end_column: 2}, grid.links(0).first)
    assert_equal "https://ruby-lang.org/", grid.links(0).last[:url]
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "source.rb"), "text")
      vt.feed("\e[H\e[2Ksource.rb:2:3")
      assert_equal [{path: File.join(directory, "source.rb"), line: 2, column: 3}], grid.file_paths(0, cwd: directory)
    end
  end

  def test_rejects_invalid_dimensions_and_scrollback_limits
    assert_raises(ArgumentError) { Tarazed::Grid.new(columns: 0) }
    assert_raises(ArgumentError) { Tarazed::Grid.new(rows: -1) }
    assert_raises(ArgumentError) { Tarazed::Scrollback.new(-1) }
  end
end
