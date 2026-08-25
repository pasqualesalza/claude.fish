# claude.fish

A [fish](https://fishshell.com) plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code):
a zoxide-style session picker plus completions for the `claude` CLI (which ships none).

## Commands

- `ccr [--all|--repo] [query]` — resume the **latest** (or best-matching) session in the current
  project (`--repo`/`-r`: this repository and its worktrees). No query → the session this terminal last resumed (remembered in the shell-global
  `_claude_fish_last_session`), else the most recent here. No match → falls back to the
  picker. In-session `/resume` is Claude's own, in-process, and invisible to the shell.
- `ccri [--all] [query]` — **interactive** fzf picker with a transcript preview.
  `ctrl-x` trashes, `ctrl-p` pins, `ctrl-o` reads the full transcript, `ctrl-/` toggles the
  preview. `ccri --trash` browses trashed sessions (enter restores).

Both run `claude --resume <id>` in the session's own working directory. `--all` searches every
project instead of just the current folder. `ccr --empty-trash` purges the trash for good.

## Layout

- **`stat` is probed GNU-first, and the order is load-bearing.** `stat -f` on GNU means
  "filesystem status": given a file it prints a multi-line block about the *filesystem* to stdout
  and only then exits non-zero, so trying BSD first poisoned every row on Linux while
  `2>/dev/null` hid the complaint. The mtime field became `Inodes: Total: … / Type: overlayfs`,
  and since it was multi-line each line became another row in the picker. That is why CI had been
  red since June. The value is now also required to be digits, whichever stat answered.
- `functions/_claude_sessions.fish` — parses `~/.claude/projects/**/*.jsonl` via `jq` into
  `id<TAB>title<TAB>cwd<TAB>path<TAB>mtime<TAB>branch<TAB>body` (most-recent first). Override the
  root with `$CLAUDE_FISH_PROJECTS_ROOT` (used by the tests). Drops sidechains and empty shells.
- `functions/_claude_sessions_table.fish` — builds the fzf table (two-line entries, `★` pins,
  `●`/`○` liveness). Emits **NUL-separated**
  records because one entry spans two lines — read them with `string split0`, feed fzf
  `--read0`. Kept as an **external command** so fzf's `reload()` can rebuild the list after a
  delete or pin; also the seam where a compiled parser could replace the jq pipeline.
  Everything visible is budgeted to `--width`, which ccri measures from `$COLUMNS` and passes
  to both the first build and the reload command (fzf's `FZF_COLUMNS` is still 0 while the UI
  sizes itself, which is exactly when the first build runs). The transcript snippet stays in
  the searched field but sits **after** padding to that width, so it is searchable and never
  visible — appending it directly is what used to make every row ~2000 columns long and look
  sliced.
  Two fragile spots: `string collect` when assembling a record (without it fish splits on the
  newline and each session shows up twice), and ccri's `--accept-nth` (fish would otherwise
  split a multi-line selection into two elements).
- `functions/_claude_widen_root.fish` — where to look when the current folder has nothing filed
  under it, shared by `ccr` and `ccri` so the two cannot drift. A session is filed under the
  directory it was **started** in and Claude Code keeps writing there afterwards; only a
  `<id>/tool-results/` sidecar appears under the new cwd (verified: this session's transcript sits
  in `-Users-…-claude-fish` while its cwd is the worktree, whose project dir holds nothing but
  `<id>/tool-results/`). So standing in a worktree, `ccr` answered "no Claude sessions found" in
  the one place it was plainly wrong. It compares the repo root against the **resolved** `$PWD` —
  git resolves symlinks and `$PWD` does not, so without that the widening fired even at the root.
- `functions/_claude_repo_root.fish` — the main checkout for `$PWD`, which is what `--repo`/`-r`
  scopes to (via `_claude_sessions --under`). Do **not** reach for `git rev-parse --show-toplevel`:
  inside a worktree that returns the worktree, i.e. the directory you already have. The common git
  dir belongs to the main checkout — a worktree's `.git` is a file pointing at it — so its parent
  is the repo everything hangs off, and from the main checkout the answer is identical. Verified
  against a real repository with a real worktree in the tests, including that `--show-toplevel`
  disagrees there.
- `functions/_claude_worktrees_table.fish` / `_claude_worktree_preview.fish` — the
  `ccri --worktrees` index: one row per worktree **that has sessions**, then enter falls through
  to the ordinary picker scoped with `_claude_sessions --under <dir>`, so preview and keys are
  unchanged. Read from the sessions rather than from `git worktree list` on purpose: a removed
  worktree still has its transcripts and is exactly what you cannot otherwise find, so it is
  listed and marked `gone`. The session titles ride in a hidden third field (joined by RS) because
  re-reading the transcripts in the preview costs about a second per cursor move.
  `--under` matches on the **cwd**, not on the encoded directory name — encoding turns every
  non-alphanumeric into `-`, so a prefix match there cannot tell `claude.fish` from
  `claude-fish2` — and it compares against both the given path and its symlink-resolved form,
  since a transcript records the shell's logical PWD (resolving only would match nothing under
  anything below /tmp on macOS).
- The cwd in a row is the **last** one in the transcript, and the head window is not enough to
  find it: a session moves (into a worktree, back out of it), `ccr` cd's into that field, and on
  a real session the head-only rule named a worktree deleted since while the session had moved
  back to the main checkout and was perfectly resumable. The worker feeds jq a `tail -n 50` chunk
  last so `last` lands on the newest record — but only when the file is longer than the head
  window, or the two overlap and the body is counted twice. Two traps in that test: `tail -n +201`
  and `wc -l` read from the START of the file, which took the list build from 594ms to **3243ms**;
  `head -n 201 | wc -l` answers the same question having read at most 201 lines, and costs nothing
  (633ms against 629ms without the chunk at all).
- `functions/_claude_list_width.fish` — the row budget from a terminal width, in one place
  because two callers need it at different moments. ccri measures `$COLUMNS` for the first build
  (fzf's `$FZF_COLUMNS` is still 0 while it sizes the UI, which is exactly when that build runs),
  and the reload command asks the table for `--width auto`, which measures `$FZF_COLUMNS` at that
  moment. That is what `--bind resize:reload(…)` is for. Measured on the real picker through a pty,
  resizing 140 → 90 columns: fzf **does** re-run the preview by itself (the turn frames went 70 →
  43 wide with the bind and without it), but it does **not** rebuild the list, so a row kept the
  budget taken at startup. With the bind `_claude_list_width` is called twice, 140 then 86; without
  it, once. A synthetic probe first suggested the preview went stale too — it was signalling the
  wrong process, the fish wrapper rather than fzf underneath it, so fzf never learned the window
  had changed and emitted nothing at all. Deliver SIGWINCH to the process **group**, the way a
  terminal does.
  What no resize can fix is `ctrl-o`: the pager's text was rendered for the width it had at launch,
  `less` cannot re-render our pipeline, and it does not even repaint until you press a key — so a
  window narrowed mid-read makes `less` wrap every frame rule. `q` then `ctrl-o` again is the whole
  workaround.
- `ccr`/`ccri` launch Claude in the session's directory and then put the shell **back**: Claude
  has no flag for a working directory (`--add-dir` only widens what tools may touch), so the cd is
  a means to an end, and leaving the shell elsewhere is a side effect nobody asked for — now more
  often a worktree buried under `.claude/worktrees`, since the recorded cwd is the current one.
  Measured by driving fish through a pty: fish skips the rest of a function when the foreground
  child is **killed** by ctrl-c, but runs it when the child catches SIGINT and exits later, which
  is what Claude Code does. So the restore holds in the normal path, and a signal-death degrades
  to the pre-0.3.0 behaviour of staying put. Claude's exit status is carried across the trip.
- `functions/_claude_place.fish` — the short where-it-lives label: last two path components
  with `.claude/worktrees` removed, so `claude.fish/picker-manage` instead of a 50-column path
  or a bare `mcp`. `functions/_claude_fit.fish` truncates to a column budget with `…`.
- `functions/_claude_picker_header.fish` / `_claude_picker_footer.fish` — the header shows only
  a transient action notice (via `transform-header`); the permanent key hints live in the footer.
- `functions/_claude_session_preview.fish` — transcript preview for fzf, with query highlight.
  Two paths: `mdcat` when installed (real markdown — see below), else a hand-rolled ANSI
  renderer. `$claude_fish_renderer=ansi` pins the fallback.
- `functions/_claude_session_markdown.fish` — the transcript as plain markdown, piped to
  `mdcat --ansi --local --image-protocol none --columns …`. We choose the structure (roles as
  `##`), mdcat does the typography. **`--local` is not optional**: without it a transcript
  mentioning an image URL would make the preview pane fetch from the network.
  Don't swap in glow: it needs `CLICOLOR_FORCE` *and* an explicit `--style` (fragile through
  fzf's nested shells), pads every line, and is 8× heavier. `gum format` never colours a pipe.
- `functions/_claude_records_jq.fish` — every jq program that reads a transcript goes through
  here, because Claude appends to a **live** one while we read it and the final line can be half
  a record. `jq -s` aborts on the first parse error, which took the whole body with it: the pane
  rendered its header and nothing else, and the session dropped out of the list — silently, and
  precisely for the sessions you look at most. Tolerant parsing was measured and rejected
  (`jq -Rs '[splits("\n") | fromjson?]'` turns a 23ms parse into 846ms). The repair is a retry
  without the last line, gated on **jq's exit status** rather than on an empty result, and
  streamed rather than captured: routing the render through a fish variable to test it cost
  220ms → 841ms, while the exit-status version is free (interleaved min-of-7: 334ms against
  345ms). `-s` slurps before it emits, so a failure can never leave half an answer behind.
  `_claude_sessions` carries the same retry in its bash worker, where `head -n 200` is what
  catches the half record on a young session.
- `functions/_claude_clip_jq.fish` — the jq that cuts a message to a budget, **shared by both
  renderers** so they cannot disagree. It walks whole units and steps down only when one will
  not fit: blocks (paragraphs, lists, fenced code, split on blank lines outside a fence) → whole
  lines → words. Cutting at an exact character count put the pane mid-sentence and mid-heading
  — a real session showed `## Sì, la k` and `: **una versione che viene riusata smette di` — which
  reads as damage rather than as a preview.
  The **last** turn is clipped from its start and every earlier one from its end (`clip($tail)`,
  in each renderer): the pane is anchored on the end of the conversation, and the last
  turn was over the 1200-character budget on all six real sessions measured — head-clipping it
  hid precisely the words the pane is opened to read. Whether anything fell outside the record
  window is asked with `tail -n (window + 1)`, which reads from the end and so costs 6ms on a
  76MB transcript; the answer becomes the notice at the top of the body, where you land when you
  scroll up.
  Every clip **must leave the fences balanced** (`balance($tail)`). Markdown has no turn
  boundaries: one fence left open by a clip landing inside a code block makes mdcat read every
  later turn as code too, so the rest of the pane arrives as literal `**` and `##` with the
  frame spine running on — and because it depends on where the clip lands, it looks like some
  sessions are broken and others fine. The hand-rolled fallback guards its own trailing chunk
  in `render`, which is why that path never showed it.
- Reading a transcript is `ctrl-o`, and it hands the **whole terminal** to `less -R +G`
  through fzf's `execute()`. That is a reversal: this file used to claim a program launched from
  `execute()` fights fzf for the terminal and that `less` wouldn't scroll. Both were wrong, and
  the pty measurements say so — ctrl-o paints the pager (+3.9KB), a page key scrolls it
  (+2.9-4.2KB), `q` redraws the picker (+15.7KB), three alternate-screen switches in and out.
  Restoring the terminal on the way in and taking it back on the way out is what `execute()` is
  for. The pane cannot match it: fzf refuses a window over 99% (`window size too large`), which
  is 132x38 of a 140x40 terminal, and it has no `/` search.
  Two things the pager needs: `+G` so it opens on the last message, where the preview pane also
  lands, and `FZF_PREVIEW_COLUMNS` set from **`FZF_COLUMNS`** — the former is preview-only and
  absent inside an `execute()`, so the render would silently fall back to 80 columns; with it the
  frame measures the full 140. Without `less` installed the old widened pane is still the
  fallback. No glow dependency: it would be a second renderer for one keystroke.
- The pane opens on the **newest** exchange, and `follow` in `--preview-window` is the only
  thing that does it. Measured by reading fzf's own scroll indicator out of a pty (it prints
  `<first-visible-line>/<total>` in the pane corner) on a 500-line preview: `follow` → 466/500,
  the end at the bottom; `+99999` → 500/500, the last line at the *top* over a blank pane;
  `+99999-/1` → also 500/500, because fzf clamps **last**, so arithmetic on a huge base never
  survives; and the `preview-bottom` action → 4/500 on `start`, `load`, `result` and `focus`
  alike, i.e. inert, since the event fires before the preview content exists. `follow` does not
  trap you at the bottom either — a manual scroll up sticks; it re-pins only when the preview is
  regenerated, which is when you move to another session.
- `functions/_claude_live_sessions.fish` — running sessions, read from
  `~/.claude/sessions/<pid>.json` and filtered by `kill -0`. **The only reliable liveness
  signal**: Claude appends with open→append→close, so no fd is ever held and `lsof` is blind.
- `functions/_claude_session_delete.fish` / `_claude_session_restore.fish` — trash and undo.
  The trash is a sibling of the projects root so the move is a same-fs `rename(2)`, and it
  mirrors the `<enc>/<id>.jsonl` layout so listing it is the same parse at a different root.
- `functions/ccr.fish`, `functions/ccri.fish` — the two commands. fzf is soft-coupled to
  fzf.fish's `_fzf_wrapper` (reused if present, plain `fzf` otherwise).
- `completions/` — hand-written `claude` flags/subcommands (+ dynamic `--resume`) and `ccr`/`ccri`.
- `tests/parse.test.fish` (jsonl parsing) and `tests/manage.test.fish` (pins, trash, restore,
  liveness — all against a throwaway copy of `tests/fixtures/`).
  The floor is **fish 4.0**, and it is measured, not inferred from which builtin arrived when: in
  an ubuntu container the suite fails 7 assertions on fish 3.7.1 and 37 on 3.3.1. The 3.7 failures
  are real, not test artifacts — a roomy record comes back as six elements instead of one (the
  `string collect` fragility above) and a header line overruns its width. `fish-actions/install-fish`
  takes no version input; on Linux it installs from the release-4 PPA, so CI covers 4.x only.
  **CI has no mdcat** — only fish, fishtape and the jq that ships with the runner image — so
  anything asserting on mdcat's output sits behind `if type -q mdcat`, and the frame pass is
  covered twice: once end to end there, once by feeding `_claude_frame_awk` a synthetic `━━ role`
  input, which runs anywhere. Nine assertions were red under those conditions before that split,
  and this branch had never been pushed, so CI had never seen them. To reproduce the CI
  environment locally, copy a test file with `set -gx PATH /usr/bin /bin` plus a directory holding
  only `jq`/`fzf` prepended — trimming PATH from *outside* does not work, because fish's own config
  puts Homebrew back in every child process, and fishtape runs each file in a child.
- `tools/render-gallery.fish` — contact sheet of every look (`turns` × `theme` × renderer) on a
  real transcript, each sample labelled with the `set -U` line that produces it. Self-locating,
  and outside `functions/`/`completions/` so fisher never installs it.
  `fish tools/render-gallery.fish [turns|themes|all] [path.jsonl]`

## Settings

Three, set with **`set -U`** (or `-x`). A plain `set -g` will NOT work: fzf runs the preview and the
list rebuild in child fish processes, which do not inherit globals.

| Variable | Values | Effect |
|---|---|---|
| `claude_fish_turns` | **`frame` (default)**, `heading` | `frame` → `┏━ user ━━━…` with a `┃` down the body, **green for user, cyan for assistant** — an awk pass, since mdcat cannot draw boxes and colours every heading identically, so this is the only mode where the two roles are distinguishable at a glance. It also eats the blank lines mdcat puts around a heading (~17 rows back on a real transcript). `heading` leaves mdcat's own `━━ user` alone |
| `claude_fish_theme` | any mdcat theme: `dark`, `light`, `nord`, `dracula`, `gruvbox-*`, `catppuccin-*`, `solarized-*` | passed to `mdcat --theme`. Name-shaped values only; anything else is dropped rather than handed to a command line. An unknown theme makes mdcat fail and the pane falls back to the ANSI renderer rather than blanking |
| `claude_fish_renderer` | *(unset)*, `ansi` | pin the built-in ANSI renderer instead of mdcat |

Turn labels are `user` and `assistant` deliberately: those are the literal values in both the
Messages API and Claude Code's own jsonl, so the labels cannot drift from the data. Not `human`
(deprecated Text-Completions vocabulary, superseded per Anthropic's migration doc) and not
`agent` — Anthropic reserves that for subagents and the Agent SDK, and these transcripts already
carry `agent-name` records for exactly those.

`claude_fish_turns` is the styling lever because mdcat has no per-element theming: choosing the
construct is what chooses the look. Unknown values fall back to the default.

A setting changed **while the picker is open** only half applies, and the seam is worth knowing:
the preview child reads it on every keystroke, while fzf's flags were fixed at launch. Toggling
`claude_fish_renderer` mid-session produced code highlighted by mdcat *and* folded by fzf's `wrap`
— each configuration is self-consistent, the transition is not. `wrap` is passed only when mdcat is
out of the picture, because the hand-rolled renderer emits long lines and needs fzf to fold them,
while mdcat wraps prose itself and deliberately does not reflow code (folding a 512-column code
line turned 56 lines into 118 rows). mdcat never emits `↳`: measured on a long code line *with*
spaces it prints all 97 characters at `--columns 60`, so any `↳` in the pane is fzf's.

**Three settings, not six.** `claude_fish_layout=compact`, `claude_fish_role_colors` and
`claude_fish_preview=full` were built and then removed before release: one line per session instead
of two, SGR overrides for the frame colours, and a pane that always rendered like read mode. Each
was a branch in the code, a row in two documents and a test, and none earned that — the frame
colours are basic ANSI precisely so they follow the terminal, and `ctrl-o` already gives the uncut
render without paying 4× on every cursor move. The shapes are in git if one is ever wanted back.

## Overridable paths

`$CLAUDE_FISH_PROJECTS_ROOT`, `$CLAUDE_FISH_SESSIONS_DIR`, `$CLAUDE_FISH_STATE_DIR`,
`$CLAUDE_FISH_TRASH_ROOT`, `$CLAUDE_FISH_LIMIT`. The tests set the first four.

## Requirements, and how the floors were measured

Not by reading changelogs for which builtin arrived when — that is how the README ended up
claiming fish 3.4, then 3.5, both wrong. Each floor was run:

- **fish 3.7+**: `docker run -i --rm -v "$PWD":/src:ro ubuntu:22.04 bash -s` with a script that
  installs fish from the distro (3.3.1 → 35 failures) or from `ppa:fish-shell/release-3`
  (3.7.1 → green). `fish-actions/install-fish` takes no version input; on ubuntu-24.04 its
  release-4 PPA gives 4.8.1, so CI runs 4.x and the container covers the floor.
  The first version of this note claimed 4.0+ on the strength of 7 failures at 3.7.1. Six of those
  were the `stat` bug below — measured on Linux and blamed on the fish version — and the seventh
  was the header-width test stripping only `m`-terminated escapes while `set_color normal` also
  emits `ESC ( B`. Both are fixed; 3.7.1 is green.
- **fzf 0.63+**: `mise x fzf@<version> -- fzf <the ccri flag set> --filter=t` walks the versions —
  0.55 rejects `--accept-nth`, 0.60 and 0.62 reject `--footer` — and then the pty probe runs the
  real picker at 0.63.0 to check it behaves, not merely parses.
- **jq 1.6+**: same real session rendered under 1.6 and 1.8.2, compared on line count, clip markers
  and fence balance.

There is no `mise.toml`, and that is deliberate: **neither fish nor mdcat is in mise's registry**,
so the two versions that actually matter cannot be pinned by it. mise is still the right tool for
*checking* a floor (`mise x fzf@0.62.0 -- …`), which is why the commands above are written down.

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
