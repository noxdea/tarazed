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
pipe-only console. Shell integration and the higher-level `Screen`, `Parser`,
and `Session` APIs remain future work.

## Development

Run `bundle install`, then `bundle exec rake test`. Validate the signatures with
`bundle exec rbs -I sig validate` and run the benchmark with
`BUDGET=1 bundle exec rake bench`.

## Contributing

Bug reports and pull requests are welcome at https://github.com/noxdea/tarazed.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
