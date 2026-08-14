# The awk program that turns mdcat's role headings into framed turns. Kept in its own
# function so the preview stays readable and this stays testable on its own.
#
# mdcat renders `## assistant` as `━━ assistant` in the theme's heading colour — the SAME
# colour for both roles, which is why plain heading mode cannot tell user from assistant at a
# glance. Framing fixes that: since awk knows the role, it colours the frame per role and
# deliberately drops mdcat's heading colour for this one element. Telling the two apart is
# worth more than following the theme here.
#
# The defaults are basic ANSI (bold green / bold cyan), which resolve against the TERMINAL's
# palette — the same palette fzf's borders, the session list and the no-dependency renderer
# use, so with mdcat's `dark`/`light` themes the pane is single-palette. A truecolor theme
# (nord, catppuccin, …) makes the pane mixed anyway — mdcat itself emits ~340 basic sequences
# alongside ~115 truecolor ones — and the frame sits with the majority. Override with
# `claude_fish_role_colors` (two SGR parameter strings) to match a truecolor theme exactly.
#
# It also swallows the blank line mdcat puts under a heading — that was the wasted vertical
# space — and runs a `┃` down the turn's body.
#
# The labels are `user` and `assistant` on purpose: they are the literal values in both the
# Messages API and Claude Code's own jsonl, so they cannot drift from the data. Not `human`
# (deprecated Text-Completions vocabulary) and not `agent` — Anthropic reserves that for
# subagents, and these transcripts already carry `agent-name` records for exactly those.
function _claude_frame_awk --description "awk program that frames each turn in the rendered preview"
    echo '
      function plain(s) { gsub(/\033\[[0-9;?]*[a-zA-Z]/, "", s); return s }
      BEGIN { inturn = 0; eat = 0; col = "\033[" acol "m" }
      {
        p = plain($0)
        if (p ~ /^━━ (user|assistant)$/) {
          role = p; sub(/^━━ /, "", role)
          col = (role == "user") ? "\033[" ucol "m" : "\033[" acol "m"
          bar = ""
          n = w - length(role) - 4
          for (i = 0; i < n; i++) bar = bar "━"
          printf "%s┏━ %s ━%s\033[0m\n", col, role, bar
          inturn = 1; eat = 1
          next
        }
        if (eat && p ~ /^[ \t]*$/) { eat = 0; next }
        eat = 0
        if (inturn) printf "%s┃\033[0m %s\n", col, $0
        else print
      }'
end
