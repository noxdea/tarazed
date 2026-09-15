# Tarazed

Tarazed is a pure Ruby terminal emulator core. It provides the
terminal cell grid, scrollback, VT parser, keyboard/mouse encoding, and a
POSIX or Windows ConPTY session without depending on an editor or UI toolkit.

## Installation

```bash
bundle add tarazed
```

Or run `gem install tarazed`.

## Usage

Feed arbitrary byte chunks into a `VT`; incomplete UTF-8 and control sequences
are retained until the next chunk.

```ruby
require "tarazed"

screen = Tarazed::Grid.new(columns: 80, rows: 24)
terminal = Tarazed::VT.new(screen)
terminal.feed("\e[32mready\e[0m\r\n")
puts screen.text
```

`Tarazed::PTY` owns a child process and feeds its output into the same grid.
It uses a POSIX PTY on macOS and Linux and ConPTY on 64-bit Windows:

```ruby
terminal = Tarazed::PTY.new(command: ["/bin/sh"], columns: 80, rows: 24)
terminal.write("printf 'hello\\n'\r")
terminal.read(timeout: 0.1)
terminal.close
```

ConPTY requires a supported 64-bit Windows release and does not fall back to a
pipe-only console.

`Tarazed::Session` adds a pump-oriented API and bounded OSC 133 command
history. Command rows and output ranges use stable absolute history rows, and
OSC 7 updates the session working directory:

```ruby
session = Tarazed::Session.new(command: ["/bin/bash"], columns: 80, rows: 24)
session.pump(timeout: 0.05)
session.commands.each do |command|
  puts "#{command.exit_status}: #{command.input} (#{command.cwd})"
end
session.close
```

Shell integration snippets for bash, zsh, and fish are packaged with the gem.
An embedding application can inject one into a new interactive shell with
`Tarazed::ShellIntegration.read(:bash)` (or `:zsh` / `:fish`). The snippets
emit prompt, input, execution, and completion markers without changing the
visible prompt.

## Development

Run `bundle install`, then `bundle exec rake test`. Validate the signatures with
`bundle exec rbs -I sig validate` and run the benchmark with
`BUDGET=1 bundle exec rake bench`.

## Contributing

Bug reports and pull requests are welcome at https://github.com/noxdea/tarazed.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
