# claude.fish

A [fish](https://fishshell.com) plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code):
a zoxide-style session picker (`ccr` / `ccri`) plus completions for the `claude`
CLI (which ships none).

Sessions are scoped to the current project by default — exactly how Claude Code
stores them — so resuming always reattaches to the right conversation instead of
spawning an empty one.

## Commands

| Command | Behaviour |
|---|---|
| `ccr` | Resume the **most recent** session in this folder — "continue where I left off". |
| `ccr <query>` | Resume the most recent session matching `<query>` (title + transcript). Falls back to the picker if nothing matches. |
| `ccri [query]` | **Interactive** fzf picker with a transcript preview. |
| `… --all` | Search across every project, not just this folder. |

Both run `claude --resume <id>` in the session's own working directory.

## Requirements

- fish 3.4+
- [`jq`](https://jqlang.github.io/jq/) and [`fzf`](https://github.com/junegunn/fzf)
- Optional: [`fzf.fish`](https://github.com/PatrickF1/fzf.fish) — if present, the
  picker reuses its `_fzf_wrapper` for a consistent look; otherwise plain `fzf` is used.

## Install

```fish
fisher install pasqualesalza/claude.fish
```

## License

[MIT](LICENSE)
