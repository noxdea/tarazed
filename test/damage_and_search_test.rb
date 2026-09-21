# frozen_string_literal: true

require_relative "test_helper"

class DamageAndSearchTest < Minitest::Test
  def test_damage_tracks_changed_rows_and_can_be_cleared
    grid = Tarazed::Grid.new(columns: 8, rows: 3, scrollback: 2)
    assert_equal 0..2, grid.damage
    grid.clear_damage
    refute grid.damage

    grid.put("a")
    assert_equal 0..0, grid.damage
    assert_equal [0], grid.damage_rows
    grid.clear_damage
    refute grid.damage
  end

  def test_synchronized_output_and_focus_notifications
    vt = Tarazed::VT.new(Tarazed::Grid.new(columns: 8, rows: 3))
    vt.feed("\e[?2026h\e[?1004h")
    assert vt.synchronized?
    assert vt.grid.synchronized?
    assert_equal "\e[I", vt.focus(active: true)
    assert_equal "\e[O", vt.focus(active: false)
    vt.feed("\e[?2026l")
    refute vt.synchronized?
    refute vt.grid.synchronized?
  end

  def test_scrollback_search_supports_literals_and_regex
    grid = Tarazed::Grid.new(columns: 6, rows: 2, scrollback: 5)
    vt = Tarazed::VT.new(grid)
    vt.feed("first\r\nsecond\r\nthird")
    assert_equal ["first"], grid.search("first").map { |result| result[:text] }
    assert_equal ["second"], grid.search("sec.*", regex: true).map { |result| result[:text] }
  end
end
