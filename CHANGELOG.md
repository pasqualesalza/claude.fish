# Changelog

All notable changes to this project are documented here.
This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1] - 2026-06-04

### Added

- Short session id in the `ccri` list (helps tell apart same-titled / forked sessions).

### Fixed

- Robustness pass from an independent code review: NUL-delimited paths (handles spaces in
  paths), the latest title record wins, no parallel-pipe interleaving, stray control/ESC bytes
  are stripped, sessions that mix sidechain and normal turns are kept, and `CLAUDE_FISH_LIMIT`
  is validated.
- `ccr <query>` now matches literally (no glob surprises); `ccr`/`ccri` report a clear error
  if `jq` is missing.
- Preview falls back to the first user message when a session has no title.
- Release tag validation anchored to `vMAJOR.MINOR.PATCH`.

## [0.2.0] - 2026-06-04

### Added

- Real session titles in the picker and `--resume` completion: uses the rename /
  AI-generated title (`✎` marks renamed sessions) instead of just the first message.
- `ccri` preview now opens with a recap header (title + "where you left off" = last
  prompt) followed by the recent conversation, with colored user/assistant turns.

### Changed

- `ccri --all` is dramatically faster (tens of seconds → <1s): parses only the most
  recent sessions, in parallel, and caps per-message work to avoid a quadratic blowup
  on huge transcripts.

### Fixed

- `claude --resume` completion no longer offers file paths alongside sessions.

## [0.1.0] - 2026-06-03

### Added

- `ccr` / `ccri` — zoxide-style session picker to find and resume Claude Code sessions
- Completions for the `claude` CLI (flags, subcommands, dynamic `--resume` with titles)
- fishtape tests for the JSONL session parsing
- CI (fish_indent + `fish -n` + fishtape) and lefthook pre-commit hooks
