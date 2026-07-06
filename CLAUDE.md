# claude.fish

A [fish](https://fishshell.com) plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code):
a zoxide-style session picker plus completions for the `claude` CLI (which ships none).

## Commands

- `ccr [--all] [query]` — resume the **latest** (or best-matching) session in the current
  project. No query → the session this terminal last resumed (remembered in the shell-global
  `_claude_fish_last_session`), else the most recent here. No match → falls back to the
  picker. In-session `/resume` is Claude's own, in-process, and invisible to the shell.
- `ccri [--all] [query]` — **interactive** fzf picker with a transcript preview.

Both run `claude --resume <id>` in the session's own working directory. `--all` searches every
project instead of just the current folder.

## Layout

- `functions/_claude_sessions.fish` — parses `~/.claude/projects/**/*.jsonl` via `jq` into
  `id<TAB>title<TAB>cwd<TAB>path<TAB>body` (most-recent first). Override the root with
  `$CLAUDE_FISH_PROJECTS_ROOT` (used by the tests). Drops sidechains and empty shells.
- `functions/_claude_session_preview.fish` — transcript preview for fzf, with query highlight.
- `functions/ccr.fish`, `functions/ccri.fish` — the two commands. fzf is soft-coupled to
  fzf.fish's `_fzf_wrapper` (reused if present, plain `fzf` otherwise).
- `completions/` — hand-written `claude` flags/subcommands (+ dynamic `--resume`) and `ccr`/`ccri`.
- `tests/parse.test.fish` + `tests/fixtures/` — fishtape tests for the jsonl parsing.

## Develop

- Format: `fish_indent -w **/*.fish`
- Lint: `fish -n <file>`
- Test: `fishtape tests/*.test.fish` (needs `fisher install jorgebucaran/fishtape`)
- Hooks: run `lefthook install` once → pre-commit runs `fish_indent --check`, `fish -n`, and
  `fishtape` on staged `.fish` changes (the same checks as CI).

## Release

- The changelog is **hand-written** in `CHANGELOG.md` ([Keep a Changelog](https://keepachangelog.com)
  format) — jot entries under `## [Unreleased]` as you go (AI can help draft them).
- To cut a release: rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` (add a fresh empty
  `## [Unreleased]` above it), commit, then `git tag vX.Y.Z && git push origin vX.Y.Z`.
- `release.yml` extracts that version's section from `CHANGELOG.md`
  (`ffurrer2/extract-release-notes`) and publishes a GitHub Release with those notes
  (`softprops/action-gh-release`). Every release is listed on the Releases page.

## Fisher note

Fisher installs from a git ref: `pasqualesalza/claude.fish` (default branch) or
`pasqualesalza/claude.fish@vX.Y.Z` to pin a tag. **GitHub Releases are human-facing notes only —
they have no effect on installation.**
