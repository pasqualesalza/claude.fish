# The awk program that turns mdcat's role headings into framed turns. Kept in its own
# function so the preview stays readable and this stays testable on its own.
#
# mdcat renders `## assistant` as `━━ assistant` in the theme's heading colour — the SAME
# colour for both roles, which is why plain heading mode cannot tell user from assistant at a
# glance. Framing fixes that: since awk knows the role, it colours the turn per role and
# deliberately drops mdcat's heading colour for this one element.
#
# The whole frame — rule, name and spine — carries the role colour. A dim rule was tried and
# rejected: the full-width bar only *looked* too loud while the rule was one column too wide
# and the terminal soft-wrapped every frame, so the pane read as broken. With the width right,
# a coloured rule separates turns cleanly and the dim version just looked washed out.
#
# The colour defaults are basic ANSI, which resolve against the TERMINAL's palette — the same
# palette fzf's borders, the session list and the no-dependency renderer use, so with mdcat's
# `dark`/`light` themes the pane is single-palette. A truecolor mdcat theme makes it mixed either
# way — mdcat emits ~340 basic sequences next to ~115 truecolor ones — which is why there is no
# setting for these two: it could not have made the pane consistent.
#
# The labels are `user` and `assistant` on purpose: they are the literal values in both the
# Messages API and Claude Code's own jsonl, so they cannot drift from the data. Not `human`
# (deprecated Text-Completions vocabulary) and not `agent` — Anthropic reserves that for
# subagents, and these transcripts already carry `agent-name` records for exactly those.
function _claude_frame_awk --description "awk program that frames each turn in the rendered preview"
    echo '
      function plain(s) { gsub(/\033\[[0-9;?]*[a-zA-Z]/, "", s); return s }
      BEGIN { inturn = 0; eat = 0; pending = 0; col = "\033[" acol "m" }
      {
        p = plain($0)
        if (p ~ /^━━ (user|assistant)$/) {
          role = p; sub(/^━━ /, "", role)
          col = (role == "user") ? "\033[" ucol "m" : "\033[" acol "m"
          bar = ""
          # 5, not 4: the rule is "┏━ " + role + " ━" + bar, which is 5 columns of box
          # drawing and spaces around the name. Getting this wrong by one makes the line
          # one column wider than the pane, so the terminal soft-wraps every single frame
          # and leaves an orphan ━ on its own row.
          n = w - length(role) - 5
          for (i = 0; i < n; i++) bar = bar "━"
          printf "%s┏━ %s ━%s\033[0m\n", col, role, bar
          inturn = 1; eat = 1; pending = 0
          next
        }
        if (eat && p ~ /^[ \t]*$/) { eat = 0; next }
        eat = 0
        if (inturn) {
          # A blank line is held rather than drawn. Flushed when real text follows — those are
          # the paragraph breaks inside a turn, and they earn their row. Dropped when a new
          # frame arrives or the input ends, because there the blank line is mdcats separator
          # between elements and the frame already separates them: it came out as a spine with
          # nothing beside it, one wasted row per turn and 40 rows of a 165-row pane in all.
          if (p ~ /^[ \t]*$/) { pending++; next }
          while (pending > 0) { printf "%s┃\033[0m\n", col; pending-- }
          printf "%s┃\033[0m %s\n", col, $0
        }
        else print
      }'
end
