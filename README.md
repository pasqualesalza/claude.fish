# claude.fish

[![CI](https://github.com/pasqualesalza/claude.fish/actions/workflows/ci.yml/badge.svg)](https://github.com/pasqualesalza/claude.fish/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A [fish](https://fishshell.com) plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code):
a zoxide-style session picker (`ccr` / `ccri`) plus completions for the `claude` CLI
(which ships none).

Sessions are scoped to the current project by default — exactly how Claude Code stores
them — so resuming always reattaches to the right conversation instead of spawning an empty one.

## Commands

| Command | Behaviour |
|---|---|
| `ccr` | Resume the session **this terminal** last opened here, else the most recent one — "continue where I left off". |
| `ccr <query>` | Resume the most recent session matching `<query>` (title + transcript). Falls back to the picker if nothing matches. |
| `ccri [query]` | **Interactive** `fzf` picker with a transcript preview. |
| `ccri --trash` | Browse trashed sessions; `enter` restores one. |
| `… --repo` · `-r` | Look in this repository **and all its worktrees**. |
| `ccri --worktrees` | Pick a git **worktree**, then a session inside it. |
| `ccr --empty-trash` | Delete every trashed session for good (asks you to type `yes`). |
| `… --all` | Search across every project, not just this folder. |

Both run `claude --resume <id>` in the session's own working directory, and put your shell back
where it was when Claude exits. Tab-completing
`claude --resume ` also lists your sessions by title.

`ccr` (no query) remembers, **per terminal**, the last session it resumed, so two windows
working in the same folder don't steal each other's session when you exit one. Switching
sessions *inside* Claude Code (its own `/resume`) happens within the `claude` process and is
invisible to the shell, so it doesn't change what a later `ccr` reopens.

## Keys in the picker

| Key | Action |
|---|---|
| `enter` | Resume (restore, in `--trash` mode) |
| `ctrl-x` | Move the session to the trash |
| `ctrl-p` | Pin / unpin — pinned sessions sort first |
| `ctrl-o` | Read the whole transcript full screen, in your pager — `/` to search, `←→` to pan, `q` to come back |
| `ctrl-/` | Hide / show the preview |
| `shift-↑↓` · `alt-↑↓` | Scroll the preview by line / by page |

Outcomes are reported in the header — why a delete was refused, what was trashed and how to
undo it — and the message clears itself on your next action.

## What the picker shows

- **Real titles** — a session's `/rename` (marked `✎`) or Claude's auto-generated title,
  not just the first message, with a short id to tell similar/forked sessions apart.
- **Age, at a glance** — `12m`, `3h`, `5d` — next to where the session lives and its git
  branch: `now · claude.fish/picker-manage · main`. Past a week the calendar date joins the
  counter (`14d 27 Aug`): one says roughly how long ago, the other says which day. Rows are
  budgeted to the pane width and end with `…` when a title is long, rather than running off the
  edge.
- **Which sessions are open right now** — `●` busy, `○` idle. Claude Code registers every
  running instance in `~/.claude/sessions/<pid>.json`, and that registry is what this reads.
- **Pins** — `★`, sorted to the top.
- **A transcript preview** with the working directory, git branch, model and size, then the
  conversation with each turn framed and coloured by role.
- **When things happened.** Each turn's frame carries the time it started, and the date as well on
  the first turn of a new day — a bare `14:05` says nothing on a three-week-old session. The
  header's title line ends with the session's span, `11 Aug 10:48 → 10 Sep 11:02`, and drops the
  second date when both fall on the same day. All in your local time, wherever you read it.

### What the preview leaves out

It opens on the newest exchange, so it is a *glance*, not the transcript. Three things are cut,
and each says so where it happens:

| Cut | Browse pane | `ctrl-o` |
|---|---|---|
| How far back it reads | the last 400 records | the last 4000 |
| Per turn | 1200 characters | 100 000 |
| Thinking blocks | hidden | shown |

Where a message was cut, a dim line says how much went: `… 55 more lines`. Its position is the
direction — at the bottom of a turn the end was dropped, at the top the beginning was.

A cut lands **between blocks**, never inside one: whole paragraphs, list items and code blocks
survive or go, so a message never stops mid-sentence. A single block over the budget steps down
to whole lines, and a single line over it to whole words.

The **last** turn keeps its *tail* while earlier turns keep their *head* — the pane is anchored
on the end of the conversation, so clipping the newest turn from the front would hide exactly
the words you opened it for. Scroll to the top and a line tells you whether earlier turns fell
outside the window.

Tool calls and their results are dropped in both modes. A reply is many records — one per text
block between tool calls — so consecutive records from the same role are merged back into one
turn, which is why the pane shows far fewer turns than the record count suggests.

## Worktrees

Sessions are scoped to the exact directory by default and `--all` covers every project on the
machine — with nothing in between, which is a problem if you work in git worktrees: from the main
checkout the picker cannot see any of the sessions that ran in them.

You rarely have to ask, though: **when the folder you are in has nothing filed under it, both
commands widen to the repository by themselves** and say so. That is the case that used to read
"no Claude sessions found" while you were sitting in the session — a session is filed under the
directory it was *started* in, and Claude Code keeps writing there after the session moves into a
worktree (only a `<id>/tool-results/` sidecar follows the new directory).

`ccri --repo` (or `-r`) is the explicit form: this repository and every worktree hanging off it.
It works on `ccr` too, which is where it is missed most — a session started in the main checkout
and continued in a worktree stays filed under the directory it was born in, so from the worktree a
bare `ccr` found nothing at all. The main checkout is located from git's *common* directory rather
than with `--show-toplevel`, which inside a worktree returns the worktree itself.

`ccri --worktrees` is the index. One row per worktree that has sessions, with how many and how
recently, then `enter` drops you into the ordinary picker scoped to that worktree — same preview,
same keys. In the preview header a worktree session is marked `⋔`.

The worktrees come from the **sessions**, not from `git worktree list`: a worktree you removed
still has its transcripts, and those are the ones you would otherwise never find again. Such a
row is marked `gone`, and so is the session's header, because resuming it cannot land in its own
directory — `ccr` says so and hands you `claude --resume <id>` instead of failing at `cd`.

The directory shown is the **last** one the session was in, not the first. Sessions move — into a
worktree, or back out of it — and it is the current directory that `ccr` needs.

## Managing sessions

`ctrl-x` moves a session's transcript into `~/.claude/.claude-fish-trash/`, a sibling of
Claude's own projects directory. Being a sibling matters: the move is a same-filesystem
`rename(2)`, so it is atomic and nothing is ever half-copied. The sidecar state Claude keys
by session id (`session-env/<id>`, `file-history/<id>`) travels with it instead of being left
orphaned.

`ccri --trash` browses what's in there and `enter` puts a session back. `ccr --empty-trash`
deletes for good, and asks you to type `yes` first.

**Trashing a session that Claude Code has open is refused.** Claude appends to a transcript
with open→append→close and never holds the file open, so removing it from under a live
process would simply leave that process recreating a truncated stub at the old path — you'd
end up with two half transcripts instead of one.

A trashed session disappears from Claude Code's own `/resume` too, and from
`claude --resume` completion: they read the same `~/.claude/projects/` tree. Restoring it
brings it back everywhere. The prompts you typed remain in `~/.claude/history.jsonl` — the
shared prompt history — because that is one file for every session, and rewriting it to strip
one session's lines is a far riskier operation than moving a transcript.

## Settings

Set these with **`set -U`** (or `-x`). A plain `set -g` will not work: `fzf` runs the preview
and the list rebuild in child fish processes, which don't inherit globals.

Change one while the picker is open and it only half applies — the preview is redrawn by a child
process that reads the setting on every keystroke, while `fzf`'s own flags were fixed when it
launched. Restart `ccri` after changing a setting.

| Variable | Values | Effect |
|---|---|---|
| `claude_fish_turns` | `frame` (default), `heading` | a frame around each turn, coloured per role, or mdcat's plain heading |
| `claude_fish_theme` | `dark`, `light`, `nord`, `dracula`, `gruvbox-*`, `catppuccin-*`, `solarized-*` | one of `mdcat`'s themes. `dark`/`light` stay on ANSI indices, so they follow your terminal's colours; the named ones deliberately override them |
| `claude_fish_renderer` | *(unset)*, `ansi` | pin the built-in renderer and ignore `mdcat` |

To see every combination on one of your own transcripts, with the `set -U` line under each
sample:

```fish
fish tools/render-gallery.fish          # or: … turns   /   … themes
```

## Requirements

Every floor below is measured, not inferred:

- **fish 3.7+** — the suite is green on 3.7.1 and on 4.8.1, run in an ubuntu container; 3.3.1 fails
  35 assertions. (3.5 is where the `path` builtin this relies on landed, but the PPA only offers
  the newest 3.x, so 3.7 is the oldest actually tested.)
- **[`fzf`](https://github.com/junegunn/fzf) 0.63+** — 0.62 and below have no `--footer`, and 0.55
  no `--accept-nth`. Verified at 0.63.0 by running the picker, not just by accepting the flags:
  frames drawn, footer rendered, rows re-fitted on resize.
- **[`jq`](https://jqlang.github.io/jq/) 1.6+** — a real session renders identically on 1.6 and
  1.8.2: same line count, same clip markers, same fence balance.
- Optional: [`fzf.fish`](https://github.com/PatrickF1/fzf.fish) — if present, the picker reuses
  its `_fzf_wrapper` for a consistent look; otherwise plain `fzf` is used.
- Optional: [`mdcat`](https://github.com/BIRSAx2/mdcat) — renders the preview as real markdown
  (tables, nested lists, syntax-highlighted code, text wrapped to the pane). Without it the
  picker uses a built-in renderer that needs nothing beyond `jq`.

## Install

```fish
fisher install pasqualesalza/claude.fish
```

## License

[MIT](LICENSE)
