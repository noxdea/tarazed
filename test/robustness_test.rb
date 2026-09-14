# frozen_string_literal: true

require_relative "test_helper"

class RobustnessTest < Minitest::Test
  def test_random_byte_chunks_do_not_crash_or_break_grid_shape
    random = Random.new(12_345)
    grid = Tarazed::Grid.new(columns: 40, rows: 8, scrollback: 20)
    vt = Tarazed::VT.new(grid)
    1_000.times do
      vt.feed(Array.new(random.rand(1..64)) { random.rand(256) }.pack("C*"))
      assert_equal 8, grid.cells.length
      assert grid.cells.all? { |row| row.length == 40 }
      assert_operator grid.scrollback.length, :<=, 20
    end
  end

  def test_unterminated_sequences_are_bounded_and_parser_recovers
    vt = Tarazed::VT.new(Tarazed::Grid.new(columns: 10, rows: 2))
    vt.feed("\e[" + ("1" * 20_000))
    assert_operator vt.instance_variable_get(:@sequence).bytesize, :<=, 1_024
    vt.feed("mOK")
    assert_includes vt.grid.text, "OK"

    vt.feed("\e]2;" + ("x" * 20_000))
    assert_operator vt.instance_variable_get(:@sequence).bytesize, :<=, 16_384
    vt.feed("\aOK")
    assert_includes vt.grid.text, "OKOK"
  end

  def test_scrollback_snapshots_are_bounded_and_immutable
    scrollback = Tarazed::Scrollback.new(2)
    cell = Tarazed::Cell.new(text: +"one", width: 1, attributes: {}.freeze)
    scrollback.push([cell])
    cell.text.replace("changed")
    scrollback.push([Tarazed::Cell.new(text: "two", width: 1, attributes: {}.freeze)])
    scrollback.push([Tarazed::Cell.new(text: "three", width: 1, attributes: {}.freeze)])

    assert_equal %w[two three], scrollback.map { |row| row.first.text }
    assert_raises(FrozenError) { scrollback.first.first.text << "!" }
  end

  def test_bulk_ascii_fast_path_preserves_partial_last_line
    grid = Tarazed::Grid.new(columns: 10, rows: 2, scrollback: 0)
    Tarazed::VT.new(grid).feed("0123456789abcdefghijKLMNO")

    assert_equal ["abcdefghij", "KLMNO"], grid.lines
    assert_equal [5, 1], [grid.cursor_x, grid.cursor_y]
  end

  def test_invalid_osc_cwd_encoding_is_ignored
    vt = Tarazed::VT.new
    vt.feed("\e]7;file:///tmp/%\a")

    assert_nil vt.cwd
  end
end
