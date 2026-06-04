# Changelog

All notable changes to this project are documented here.
This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
