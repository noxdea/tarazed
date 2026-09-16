<h1 align="center">Tarazed</h1>

<p align="center">
  <strong>Pure Ruby terminal emulator core</strong>
</p>

<p align="center">
  <a href="https://rubygems.org/gems/tarazed"><img src="https://img.shields.io/gem/v/tarazed.svg?colorB=319e8c" alt="Gem Version"></a>
  <a href="https://rubygems.org/gems/tarazed"><img src="https://img.shields.io/gem/dt/tarazed.svg" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/ruby-%3E%3D%203.1-ruby.svg" alt="Ruby Version">
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#pty-sessions">PTY Sessions</a> ·
  <a href="#command-history">Command History</a> ·
  <a href="#shell-integration">Shell Integration</a>
</p>

---

Tarazed is a pure Ruby terminal emulator core. It provides the
terminal cell grid, scrollback, VT parser, keyboard/mouse encoding, and a
POSIX or Windows ConPTY session without depending on an editor or UI toolkit.

## Features

- Unicode-aware cell grid with bounded scrollback
- Chunk-safe VT parsing for terminal controls, input, links, and selection
- Keyboard, mouse, bracketed-paste, and terminal-reply encoding
- POSIX PTY and 64-bit Windows ConPTY sessions behind one API
- OSC 133 command history and OSC 7 working-directory tracking
- Packaged shell integration for bash, zsh, and fish

## Installation

```bash
bundle add tarazed
```

Or run `gem install tarazed`.

Tarazed supports Ruby 3.1 and later.

## Quick Start

Feed arbitrary byte chunks into a `VT`; incomplete UTF-8 and control sequences
are retained until the next chunk.

```ruby
require "tarazed"

screen = Tarazed::Grid.new(columns: 80, rows: 24)
terminal = Tarazed::VT.new(screen)
terminal.feed("\e[32mready\e[0m\r\n")
puts screen.text
```

## PTY Sessions

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

## Command History

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

## Shell Integration

Shell integration snippets for bash, zsh, and fish are packaged with the gem.
An embedding application can inject one into a new interactive shell with
`Tarazed::ShellIntegration.read(:bash)` (or `:zsh` / `:fish`). The snippets
emit prompt, input, execution, and completion markers without changing the
visible prompt.

## Development

```bash
bundle install
bundle exec rake test
bundle exec rbs -I sig validate
BUDGET=1 bundle exec rake bench
gem build --strict tarazed.gemspec
```

## Contributing

Bug reports and pull requests are welcome at https://github.com/noxdea/tarazed.

## License

Tarazed is available under the [MIT License](LICENSE.txt).
