# ADR 002: Derive shell history from terminal protocols

- Status: Accepted
- Date: 2026-09-15

## Context

Embedders need command boundaries, exit status, and working directories without
parsing shell prompts or depending on a particular shell. Terminal output is an
untrusted, chunked byte stream, and retained history must stay bounded.

## Decision

The existing VT parser consumes OSC 133 and OSC 7 alongside other bounded OSC
sequences. Completed commands are immutable values retained in a count-bounded
history. Rows are the grid's cumulative history coordinates, so later
scrollback eviction does not change recorded ranges. Malformed markers and
working-directory values do not enter the model.

`Session` remains a thin PTY facade. Shell-specific behavior stays in packaged
bash, zsh, and fish snippets instead of the emulator core.

## Consequences

Applications can navigate command output consistently on POSIX and ConPTY.
Command input is reconstructed from retained terminal cells and is therefore
limited by scrollback and a 64 KiB per-command cap.
