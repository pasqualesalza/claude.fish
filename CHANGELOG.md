# Changelog

All notable changes to this project are documented here.
This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Times in the preview.** Each turn's frame carries the time it started, with the date as well
  on the first turn of a new day; the header's title line ends with the session's span
  (`11 Aug 10:48 → 10 Sep 11:02`), collapsed to one date when it all happened on one. Local time,
  taken from the `timestamp` every record carries.
- **The age column keeps its counter and gains a date past a week** (`14d 27 Aug`): the counter
  says roughly how long ago, the date says which day, and beyond a few days only the pair answers
  both.

## [0.3.1] - 2026-08-25

### Fixed

- **Backing out of the picker no longer reports an error.** `fzf` exits 130 on esc/ctrl-c and 1 on
  no match, and `ccri` propagated those verbatim, so the prompt showed a failure every time you
  opened the picker and changed your mind. A real failure — 2 from fzf, 127 for a missing fzf —
  still propagates.

## [0.3.0] - 2026-08-25

The picker gains a write side, a preview worth reading, and an answer for git worktrees.
`CLAUDE.md` carries the measurements behind each of these.

### Added

- **Trash a session with `ctrl-x`**, restore it with `ccri --trash` + `enter`, empty it for good
  with `ccr --empty-trash`. The transcript moves to `~/.claude/.claude-fish-trash/`, a sibling of
  the projects root, so the move is a same-filesystem `rename(2)`; the sidecar state Claude keys by
  session id travels with it. A trashed session also stops appearing in Claude Code's own
  `/resume`, and comes back when restored.
- **Trashing a session Claude has open is refused**, with the reason in the header. Liveness comes
  from `~/.claude/sessions/<pid>.json` filtered by `kill -0` — the only signal that works, since
  Claude appends with open→append→close and never holds the file open.
- **Pins** with `ctrl-p`: `★`, sorted to the top, kept in `$XDG_STATE_HOME/claude.fish/pins`.
- **A list you can read**: two lines per session — title, then `age · place · branch` — with `●`
  busy / `○` idle markers, and every row budgeted to the pane width so it ends on purpose. The
  transcript snippet stays searchable but is pushed past the border, never seen.
- **A preview that renders real markdown** when [`mdcat`](https://github.com/BIRSAx2/mdcat) is
  installed: tables, nested lists, highlighted code, each turn in a frame coloured by role (green
  user, cyan assistant). Without mdcat a built-in renderer does the same job with nothing but `jq`.
  Above it, three pinned lines: title, age, where it lives, branch, model, liveness, short id.
- **The pane opens on the newest exchange** and cuts between blocks, never mid-sentence: whole
  paragraphs, list items and code blocks survive or go, and a dim `… 55 more lines` says how much
  went and from which end. Tool calls are dropped and one reply is shown as one turn.
- **`ctrl-o` reads the whole transcript full screen**, in `less`: `/` to search, `q` to come back.
- **Worktrees.** `--repo` / `-r` scopes to this repository *and* its worktrees; `ccri --worktrees`
  lists the worktrees that have sessions and drops you into the picker scoped to the one you pick.
  A worktree session is marked `⋔` in the header, and one whose directory is gone says so — that
  list is built from the sessions, not from `git worktree list`, so a worktree you removed is still
  findable.
- **Three settings**, all with `set -U`: `claude_fish_turns`, `claude_fish_theme`,
  `claude_fish_renderer`. `tools/render-gallery.fish` shows every combination on your own
  transcript.

### Changed

- **The shell comes back where it was** when Claude exits. Both commands still launch it in the
  session's own directory — Claude has no flag for one — and Claude's exit status survives.
- **The directory shown is the one the session is in now**, not the one it started in. Sessions
  move into worktrees and back out, and `ccr` cd's into that field.
- **List rows re-fit when the window is resized**, and the picker takes the whole terminal.
- **Requirements are measured, not assumed**: fish 4.0+ (3.7.1 fails 7 assertions, 3.3.1 fails 37),
  fzf 0.63+ (0.62 has no `--footer`), jq 1.6+. The README says how each was checked.

### Fixed

- **"no Claude sessions found" while you were sitting in the session.** A session is filed under
  the directory it was *started* in and Claude keeps writing there after it moves, so from a
  worktree the folder held no transcript at all. Both commands now widen to the repository when the
  current folder has nothing filed under it, and say so.
- `ccr <query>` falling through to the picker now keeps the scope it was given.
- **The session list was broken on Linux.** `stat` was probed BSD-first, and on GNU `stat -f`
  prints a multi-line block about the *filesystem* to stdout before failing — so the mtime field
  filled up with `Inodes:` and `Type: overlayfs`, and every line of it became another row in the
  picker. Probed GNU-first now, with the value required to be digits. This is also why CI had been
  red since June.

## [0.2.2] - 2026-07-06

### Fixed

- `ccr <query>` now actually matches: it used `string contains`, which is **not** a fish
  subcommand, so every query errored and fell back to the picker (broken on all fish since
  the literal-match change). Replaced with a regex-escaped `string match`, keeping the
  literal (non-glob) semantics. Now covered by a test.
- `ccr` (no query) now re-opens the session **this** terminal last resumed instead of
  whichever session in the project was most recently modified. Two windows resuming
  sessions in the same folder no longer steal each other's session on exit. If that session
  is gone it falls back to the newest, and an explicit `ccr <query>` still wins. Both `ccr`
  and the `ccri` picker record the resumed session so a later bare `ccr` follows it.

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
