# Changelog

## Unreleased

## 0.2.2 - 2026-09-17

- Drain final Windows ConPTY output to EOF after the primary process exits without racing resize or close.

## 0.2.1 - 2026-09-16

- Report and cache natural Windows ConPTY process exit status through the cross-platform `PTY#status` API.

## 0.2.0 - 2026-09-16

- Track OSC 133 command boundaries, input, output rows, exit status, and OSC 7 working directories in bounded history.
- Add a pump-oriented `Tarazed::Session` API and shell integration snippets for bash, zsh, and fish.

## 0.1.0 - 2026-09-16

- Initial release.
