# The preview's header, built here rather than handed to the markdown renderer.
#
# It emits EXACTLY three lines, each truncated to the pane width so nothing ever wraps. That
# fixed count is the point: fzf's `--preview-window ~N` pins the first N lines while the rest
# scrolls, and N has to be a constant. Left to mdcat the header was six to eight lines
# depending on how long the branch name happened to be, so it could not be pinned at all.
#
#   1  title
#   2  age · place · branch · model · liveness · short id
#   3  a rule separating the header from the transcript
#
# There used to be a fourth line quoting the last thing you typed — the "where you left off"
# cue. It is gone because the pane now opens scrolled to the bottom, so the last exchange is
# right there in full instead of squeezed onto one truncated line.
#
# The fields come from one jq over the same bounded record window the body uses, so this costs
# a single extra jq (~15ms) and never a second pass over a large transcript.
function _claude_session_head --description "Emit the preview's fixed three-line header"
    set -l path $argv[1]
    set -l width 80
    string match -qr '^[0-9]+$' -- "$argv[2]"; and set width $argv[2]

    test -n "$path"; and test -f "$path"; or return 0
    type -q jq; or return 0

    set -l id (string replace -r '\.jsonl$' '' -- (path basename "$path"))
    set -l mtime (stat -f '%m' "$path" 2>/dev/null)
    test -n "$mtime"; or set mtime (stat -c '%Y' "$path" 2>/dev/null)

    set -l live
    for l in (_claude_live_sessions)
        set -l lp (string split \t -- $l)
        test "$lp[1]" = "$id"; and set live "open ($lp[2])"
    end

    # Title, branch, model and the last prompt, tab-separated on one line.
    set -l prog '
      def nz: . != null and . != "";
      def msgtext(m):
        (m.content) as $c
        | ( if   ($c|type) == "string" then $c
            elif ($c|type) == "array"  then
              ([ $c[0:20][] | if type=="object" then (.text // "") elif type=="string" then . else "" end ] | join(" "))
            else "" end );
      [ .[] | select(type=="object") ] as $recs
      | ( [ $recs[] | select(.type=="custom-title") | .customTitle ] | last ) as $custom
      | ( [ $recs[] | select(.type=="ai-title") | .aiTitle ] | last ) as $ai
      | ( [ $recs[] | select(.type=="agent-name") | .agentName ] | last ) as $agent
      | ( [ $recs[] | select(.type=="user" and ((.isMeta // false) | not))
            | msgtext(.message) | select(nz)
            | select(test($injected_re) | not) ]
          | first ) as $firstuser
      | [ ( if ($custom | nz) then "✎ " + $custom
            elif ($ai | nz) then $ai
            elif ($agent | nz) then $agent
            elif ($firstuser | nz) then ($firstuser | .[0:200])
            else "(untitled)" end | gsub("[\n\r\t]+"; " ") ),
          ( [ $recs[] | .gitBranch // empty | select(nz) ] | last // "" ),
          ( [ $recs[] | select(.type=="assistant") | .message.model // empty | select(nz) ] | last // ""
            | sub("^claude-"; "") ),
          # The LAST cwd, which is the rule the list uses. Read from the first one instead — as a
          # grep -m1 over the file used to do here — and a session that moved directory reports
          # where it started: this very session began in the main checkout and moved into a
          # worktree, so the row said `claude.fish/picker-manage` while the header said
          # `claude.fish`. Same session, two different places, depending on which pane you read.
          ( [ $recs[] | .cwd // empty | select(nz) ] | last // "" ) ]
      | @tsv'

    set -l meta (_claude_records_jq "$path" 400 --arg injected_re (_claude_injected_re) "$prog")
    set -l f (string split \t -- $meta)
    set -l title $f[1]
    set -l branch $f[2]
    set -l model $f[3]
    test -n "$title"; or set title '(untitled)'

    set -l cwd $f[4]

    # Same field order as a list row, so the two read alike.
    set -l facts
    test -n "$mtime"; and set -a facts (string trim -- (_claude_reltime $mtime))
    set -l place (_claude_place "$cwd")
    # `⋔` marks a session that lives in a git worktree, which `place` alone cannot say: it renders
    # `repo/name` for a worktree and for an ordinary subdirectory alike. PITCHFORK because it is
    # one column wide in every terminal (East Asian Width N) and sits in Mathematical Operators,
    # which nearly every monospace font covers — U+2442 OCR FORK reads better and is far likelier
    # to arrive as a blank box.
    string match -q '*/.claude/worktrees/*' -- "$cwd"; and set place "⋔ $place"
    test -n "$place"; and set -a facts $place
    # A worktree gets removed while its transcripts stay behind, and then resuming cannot land in
    # its own directory. Saying so here is what makes the state actionable rather than a surprise
    # at the moment you press enter.
    if test -n "$cwd"; and not test -d "$cwd"
        set -a facts 'directory gone'
    end
    test -n "$branch"; and set -a facts $branch
    test -n "$model"; and set -a facts $model
    test -n "$live"; and set -a facts $live
    set -a facts (string sub -l 8 -- $id)

    set -l bold (set_color -o)
    set -l dim (set_color -d)
    set -l rst (set_color normal)

    # The title line is nearly empty — 16 of 88 on a real session — so the session's span goes
    # there, right-aligned: for anything older than today the clock alone says nothing, and this
    # is the line you read before deciding to resume. The start comes from the FIRST record
    # (`head -n 1`, one line read) and the end from the mtime we already have; when both fall on
    # the same day the date is not repeated. Dropped entirely if the title would have to give up
    # room for it.
    set -l span
    if test -n "$mtime"
        # The FIRST record carries no timestamp — a transcript opens with metadata — so take the
        # first one that has any. `grep -m1` stops at that line instead of reading the file.
        set -l first (string replace -r '.*"timestamp":"' '' -- (grep -m1 -ao '"timestamp":"[^"]*"' "$path" 2>/dev/null) | string replace '"' '')
        if test -n "$first"
            set -l fe (_claude_epoch "$first")
            if string match -qr '^[0-9]+$' -- "$fe"
                set -l d1 (date -r $fe '+%d %b' 2>/dev/null; or date -d "@$fe" '+%d %b' 2>/dev/null)
                set -l t1 (date -r $fe '+%H:%M' 2>/dev/null; or date -d "@$fe" '+%H:%M' 2>/dev/null)
                set -l d2 (date -r $mtime '+%d %b' 2>/dev/null; or date -d "@$mtime" '+%d %b' 2>/dev/null)
                set -l t2 (date -r $mtime '+%H:%M' 2>/dev/null; or date -d "@$mtime" '+%H:%M' 2>/dev/null)
                if test "$d1" = "$d2"
                    set span "$d1 $t1 → $t2"
                else
                    set span "$d1 $t1 → $d2 $t2"
                end
            end
        end
    end

    set -l titleline (_claude_fit "$title" $width)
    if test -n "$span"
        set -l room (math $width - (string length -- $span) - 2)
        if test $room -ge 12
            set -l t (_claude_fit "$title" $room)
            set -l gap (string repeat -n (math $width - (string length -- $t) - (string length -- $span)) ' ')
            set titleline "$bold$t$rst$gap$dim$span"
        end
    end
    echo "$titleline$rst"
    echo "$dim"(_claude_fit (string join ' · ' $facts) $width)"$rst"
    echo "$dim"(string repeat -n $width ─)"$rst"
end
