# frozen_string_literal: true

require_relative "../lib/tarazed"

size = 16 * 1024 * 1024
payload = ("0123456789abcdef" * (size / 16)).b
grid = Tarazed::Grid.new(columns: 80, rows: 24, scrollback: 0)
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
Tarazed::VT.new(grid).feed(payload)
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
megabytes_per_second = size.fdiv(1024 * 1024).fdiv(elapsed)
raise "terminal output was corrupted" unless grid.lines.last.end_with?("0123456789abcdef")

iterations = 10_000
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
iterations.times { grid.lines }
elapsed_lines = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
line_extraction_ms = elapsed_lines.fdiv(iterations) * 1_000

puts format("terminal feed: %.1f MB/s", megabytes_per_second)
puts format("80x24 line extraction: %.3f ms", line_extraction_ms)

if ENV["BUDGET"] == "1"
  raise format("terminal feed below 20 MB/s: %.1f", megabytes_per_second) if megabytes_per_second < 20
  raise format("line extraction exceeded 0.2 ms: %.3f", line_extraction_ms) if line_extraction_ms > 0.2
end
