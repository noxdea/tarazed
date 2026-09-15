# ADR 001: Keep terminal state independent of renderers

- Status: Accepted
- Date: 2026-09-15

## Context

A terminal emulator interprets a child process's byte stream into screen state.
An editor or UI toolkit consumes that state but should not define its storage,
Unicode width rules, process lifetime, or protocol behavior.

## Decision

Tarazed exposes the existing cell grid, bounded scrollback, VT parser, and
PTY facade as standalone Ruby objects. The facade selects a POSIX PTY on macOS
and Linux or a Fiddle-based ConPTY backend on 64-bit Windows. It depends
directly on `unicode-display_width`; scrollback uses a bounded Array because
the default 10,000-row limit does not justify a persistent tree dependency.

Higher-level screen, parser, session, and shell integration APIs remain outside
the extracted API.

## Consequences

Tarazed can be embedded without Canopus, Denebola, or Zaniah. Unsupported or
32-bit Windows systems fail clearly when ConPTY cannot be loaded.
