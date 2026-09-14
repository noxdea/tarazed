# ADR 001: Keep terminal state independent of renderers

- Status: Accepted
- Date: 2026-09-15

## Context

A terminal emulator interprets a child process's byte stream into screen state.
An editor or UI toolkit consumes that state but should not define its storage,
Unicode width rules, process lifetime, or protocol behavior.

## Decision

Tarazed exposes the existing cell grid, bounded scrollback, VT parser, and
POSIX PTY as standalone Ruby objects. It depends directly on
`unicode-display_width`; scrollback uses a bounded Array because the default
10,000-row limit does not justify a persistent tree dependency.

Windows PTY support and higher-level screen, parser, session, and shell
integration APIs remain outside 0.1. A Windows `PTY` construction fails with a
clear `Tarazed::Error` until ConPTY is implemented.

## Consequences

Tarazed can be embedded without Canopus, Denebola, or Zaniah. The public 0.1
behavior stays aligned with the extracted implementation, while Windows users
can still use the portable grid and VT parser.
