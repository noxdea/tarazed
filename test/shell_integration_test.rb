# frozen_string_literal: true

require_relative "test_helper"

class ShellIntegrationTest < Minitest::Test
  def test_tracks_split_command_markers_cwd_and_bounded_history
    completed = []
    grid = Tarazed::Grid.new(columns: 20, rows: 3, scrollback: 2)
    vt = Tarazed::VT.new(grid, command_limit: 2, on_command: ->(command) { completed << command })

    bytes = "\e]7;file://host/tmp/a%20b\e\\" + command_sequence("echo 日本", "one", 0) +
      command_sequence("false", "two", 1) + command_sequence("true", "three", 0)
    bytes.bytes.each { |byte| vt.feed(byte.chr) }

    assert_equal Gem.win_platform? ? "//host/tmp/a b" : "/tmp/a b", vt.cwd
    assert_equal [2, 3], vt.commands.map(&:id)
    assert_equal ["false", "true"], vt.commands.map(&:input)
    assert_equal [1, 0], vt.commands.map(&:exit_status)
    assert_equal 3, completed.length
    assert completed.all?(&:frozen?)
    assert vt.commands.all? { |command| command.started_at.is_a?(Time) && command.finished_at >= command.started_at }
    assert vt.commands.all? { |command| command.output_range.cover?(command.prompt_row) }
    assert_raises(FrozenError) { vt.commands.last.input << "!" }
    assert vt.commands.last.output_range.frozen?
    assert vt.commands.last.started_at.frozen?
    assert vt.commands.last.finished_at.frozen?
    assert_operator grid.history_row, :>, grid.rows
  end

  def test_rejects_malformed_markers_and_cwd_values_then_recovers
    vt = Tarazed::VT.new(command_limit: 1)
    vt.feed("\e]7;file:///safe\a")
    vt.feed("\e]7;file:///bad%00path\a\e]7;file://user@host/tmp\a")
    vt.feed("\e]7;file:///bad\xff\a".b)
    assert_equal "/safe", vt.cwd

    vt.feed("\e]133;A\a$ \e]133;B\abad\e]133;D;0\a")
    assert_empty vt.commands
    vt.feed("\e]133;C\a\e]133;D;-1\a\e]133;D;4294967296\a\e]133;D;0;ignored\a")
    assert_empty vt.commands
    vt.feed("\e]133;D;7\a")
    assert_equal 7, vt.commands.first.exit_status
    assert_equal "bad", vt.commands.first.input

    assert_raises(ArgumentError) { Tarazed::VT.new(command_limit: -1) }
  end

  def test_zero_history_still_delivers_completed_commands
    completed = []
    vt = Tarazed::VT.new(command_limit: 0, on_command: ->(command) { completed << command })
    vt.feed(command_sequence("pwd", "/tmp", 0))

    assert_empty vt.commands
    assert_equal ["pwd"], completed.map(&:input)
  end

  def test_clear_commands_discards_completed_and_pending_history
    vt = Tarazed::VT.new
    vt.feed(command_sequence("done", "output", 0))
    vt.feed("\e]133;A\a$ \e]133;B\apending\e]133;C\a")

    assert_same vt, vt.clear_commands
    assert_empty vt.commands
    vt.feed("\e]133;D;1\a")
    assert_empty vt.commands
  end

  def test_command_input_preserves_soft_wraps_and_utf8_cap
    exact = Tarazed::VT.new(Tarazed::Grid.new(columns: 2, rows: 2))
    exact.feed("\e]133;A\a>>\e]133;B\a\e]133;C\a\e]133;D;0\a")
    assert_empty exact.commands.first.input

    grid = Tarazed::Grid.new(columns: 80, rows: 4, scrollback: 1_000)
    vt = Tarazed::VT.new(grid)
    input = ("a" * 65_535) + "日"
    vt.feed("\e]133;A\a\e]133;B\a#{input}\e]133;C\a\e]133;D;0\a")

    captured = vt.commands.first.input
    assert_equal "a" * 65_535, captured
    assert captured.valid_encoding?
    refute_includes captured, "\n"
  end

  def test_command_input_keeps_all_retained_cells_after_earlier_rows_are_evicted
    grid = Tarazed::Grid.new(columns: 4, rows: 2, scrollback: 1)
    vt = Tarazed::VT.new(grid)
    vt.feed("\e]133;A\a$ \e]133;B\aabcdefghijklmnop\e]133;C\a\e]133;D;0\a")

    assert_equal "ghijklmnop", vt.commands.first.input
  end

  def test_duplicate_input_marker_does_not_discard_already_captured_input
    vt = Tarazed::VT.new
    vt.feed("\e]133;A\a$ \e]133;B\aone\e]133;B\atwo\e]133;C\a\e]133;D;0\a")

    assert_equal "onetwo", vt.commands.first.input
  end

  def test_windows_cwd_normalizes_local_drives_and_remote_shares
    vt = Tarazed::VT.new
    Gem.stub(:win_platform?, true) do
      vt.feed("\e]7;file:///C:/Users/me\a")
      assert_equal "C:/Users/me", vt.cwd
      vt.feed("\e]7;file://server/share/work\a")
      assert_equal "//server/share/work", vt.cwd
    end
  end

  def test_resizing_while_on_alternate_screen_preserves_primary_history_rows
    grid = Tarazed::Grid.new(columns: 4, rows: 4, scrollback: 10)
    vt = Tarazed::VT.new(grid)
    vt.feed("a\r\nb\r\nc\r\nd")
    original_row = grid.history_row

    grid.alternate(true)
    grid.resize(columns: 4, rows: 2)
    grid.alternate(false)

    assert_equal original_row, grid.history_row
    assert_equal 2, grid.scrollback.total
  end

  def test_shell_snippets_are_discoverable_and_contain_all_markers
    %i[bash zsh fish].each do |shell|
      path = Tarazed::ShellIntegration.path("/bin/#{shell}")
      assert File.file?(path)
      assert_equal File.binread(path), Tarazed::ShellIntegration.read(shell)
      assert_includes File.binread(path), "133;A"
      assert_includes File.binread(path), "133;B"
      assert_includes File.binread(path), "133;C"
      assert_includes File.binread(path), "133;D"
      assert_includes File.binread(path), "\\e]7;file://"
    end
    assert_equal Tarazed::ShellIntegration.path("bash"), Tarazed::ShellIntegration.path("BASH.EXE")
    assert_raises(ArgumentError) { Tarazed::ShellIntegration.path("sh") }
  end

  private

  def command_sequence(input, output, status)
    "\e]133;A\e\\$ \e]133;B\e\\#{input}\e]133;C\e\\\r\n#{output}\r\n\e]133;D;#{status}\a"
  end
end
