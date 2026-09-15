# frozen_string_literal: true

require_relative "test_helper"

class SessionTest < Minitest::Test
  def test_pumps_a_child_into_screen_and_command_history
    output = "\e]7;file:///tmp\e\\\e]133;A\e\\$ \e]133;B\e\\echo ok\e]133;C\e\\\r\nok\r\n\e]133;D;0\a"
    child = "STDOUT.binmode; STDOUT.write(#{output.dump}); STDOUT.flush"
    session = Tarazed::Session.new(command: [RbConfig.ruby, "-e", child], columns: 40, rows: 4)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    while session.commands.empty? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      session.pump(timeout: 0.1)
    end

    assert_same session.grid, session.screen
    assert_equal "/tmp", session.cwd
    assert_equal "echo ok", session.commands.first.input
    assert_includes session.screen.text, "ok"
  ensure
    session&.close
  end
end
