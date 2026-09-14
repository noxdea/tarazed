# frozen_string_literal: true

require_relative "test_helper"
require "json"

class GoldenTest < Minitest::Test
  FIXTURES = JSON.parse(File.read(File.join(__dir__, "fixtures", "vt_golden.json"))).freeze

  def test_extracted_canopus_snapshots
    FIXTURES.each do |fixture|
      grid = Tarazed::Grid.new(columns: 12, rows: 4, scrollback: 3)
      vt = Tarazed::VT.new(grid)
      chunks(fixture).each { |chunk| vt.feed(chunk) }

      assert_equal fixture["lines"], grid.lines, fixture["name"]
      assert_equal fixture["cursor"], [grid.cursor_x, grid.cursor_y], fixture["name"]
      assert_equal fixture["scrollback"], grid.scrollback.map { |row| row.map(&:text).join.rstrip }, fixture["name"] if fixture["scrollback"]
      assert_equal fixture["history_widths"], grid.scrollback.map { |row| row.first(5).map(&:width) }, fixture["name"] if fixture["history_widths"]
      assert_equal fixture["title"], vt.title, fixture["name"] if fixture.key?("title")
      assert_equal fixture["cwd"], vt.cwd, fixture["name"] if fixture.key?("cwd")
      Array(fixture["cells"]).each { |cell| assert_cell(grid, cell, fixture["name"]) }
    end
  end

  private

  def chunks(fixture)
    return [fixture.fetch("input")] unless fixture["chunk_size"]

    fixture.fetch("input").b.bytes.each_slice(fixture.fetch("chunk_size")).map { |bytes| bytes.pack("C*") }
  end

  def assert_cell(grid, expected, message)
    cell = grid[expected.fetch("row"), expected.fetch("column")]
    actual = {
      "text" => cell.text,
      "width" => cell.width,
      "foreground" => cell.foreground,
      "background" => cell.background,
      "attributes" => cell.attributes.transform_keys(&:to_s),
      "hyperlink" => cell.hyperlink
    }
    expected = expected.reject { |key, _| ["row", "column"].include?(key) }
    expected.each do |key, value|
      value.nil? ? assert_nil(actual[key], "#{message}: #{key}") : assert_equal(value, actual[key], "#{message}: #{key}")
    end
  end
end
