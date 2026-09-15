# frozen_string_literal: true

require_relative "test_helper"
require "open3"

class IsolationTest < Minitest::Test
  def test_entrypoint_does_not_load_editor_or_ui_code
    root = File.expand_path("..", __dir__)
    script = <<~'RUBY'
      require "tarazed"
      abort "editor dependency loaded" if defined?(Canopus) || defined?(Zaniah) || defined?(Denebola)
      abort "Windows backend loaded eagerly" if defined?(Tarazed::Windows::ConPTY)
      abort "Windows backend loaded on POSIX" if !Gem.win_platform? && $LOADED_FEATURES.any? { |path| path.end_with?("/fiddle.rb") }
      puts Tarazed::Grid.new(columns: 2, rows: 1).columns
    RUBY
    output, status = Open3.capture2e({"RUBYLIB" => nil, "RUBYOPT" => nil}, Gem.ruby, "-I#{File.join(root, 'lib')}",
      "-e", script, chdir: root)

    assert status.success?, output
    assert_equal "2", output.lines.last&.strip
  end
end
