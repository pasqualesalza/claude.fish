# The transcript as plain markdown, for a real renderer (mdcat) to typeset.
#
# This splits the job the way the hand-rolled path cannot: we decide the *structure*
# (which turns, in what order, how the role is marked) and the renderer decides the
# *typography* (wrapping at the right width, tables, nested lists, syntax-highlighted
# code). Roles are `##` headings because mdcat draws those as a coloured rule + name.
#
# It emits the TURNS only. The header is built by _claude_session_head instead, because fzf
# can pin the first N preview lines with `--preview-window ~N` and N must be constant — left to
# mdcat the header ran six to eight lines depending on how long a branch name was.
function _claude_session_markdown --description "Emit a Claude session transcript as plain markdown"
    argparse f/full -- $argv 2>/dev/null; or return 1
    set -l path $argv[1]
    set -l lines 400
    set -l cap 1200
    set -l think 0
    if set -q _flag_full
        set lines 4000
        set cap 100000
        set think 1
    end

    if test -z "$path"; or not test -f "$path"
        echo "(no session selected)"
        return
    end
    type -q jq; or begin
        echo "(jq not found)"
        return
    end

    # Roles are always `##` headings. The preview then either frames them (the default) or
    # leaves mdcat's own `━━ user` rendering alone — those are the only two looks worth
    # keeping. Earlier versions also offered a full-width rule, a lighter `###` and a
    # blockquote; all three were exploration leftovers, and once framing could colour the two
    # roles differently none of them had a reason to exist (the blockquote also italicised
    # whole turns and its own headings collided with the role marker).

    # tool_use / tool_result blocks carry neither .text nor .thinking, so they drop out
    # here — the same noise policy cchb and ccresume adopt. Thinking is held back too,
    # except in read mode.
    set -l prog (_claude_clip_jq | string collect)'
      def nz: . != null and . != "";
      # Claude Code injects machinery into the transcript as ordinary `user` turns —
      # task notifications, system reminders, command output — and they are NOT flagged
      # isMeta, so that field cannot tell them apart from something you typed. They arrive
      # as XML-ish blocks, and in a preview they are pure noise: a wall of <task-id> and
      # <output-file> where a question should be. Matched on a short, conservative list of
      # opening tags rather than "anything starting with <", so a message that genuinely
      # begins with markup survives.
      def injected: test($injected_re);
      def turnblock($role; $text): "\n## " + $role + "\n\n" + $text;
      # Both clip markers say which END went missing. The cut itself walks whole blocks —
      # see _claude_clip_jq: a message that stops mid-sentence reads as damage, not a preview.
      # The last turn keeps its tail because the pane is anchored on the end of the
      # conversation; measured across six real sessions it was over budget in all six, so
      # head-clipping it hid precisely the words the pane is opened to read.
      def clip($tail):
        if (length <= $cap) then .
        else . as $t
          | ($t | split("\n") | length) as $was
          | clipped($tail; $cap) as $k
          | ($was - ($k | split("\n") | length)) as $gone
          | (if $gone > 1 then "*… " + ($gone|tostring) + " more lines*" else "*… more*" end) as $mark
          # The marker sits where the cut is, so its POSITION says which end went missing and the
          # text does not have to. A bare … said neither, and the first question it got was
          # "what are those?".
          | if $tail then $mark + "\n\n" + $k else $k + "\n\n" + $mark end
        end;
      def msgtext(m):
        (m.content) as $c
        | ( if   ($c|type) == "string" then $c
            elif ($c|type) == "array"  then
              ([ $c[0:80][] | if type=="object" then (.text // (if $think == 1 then .thinking else null end) // "")
                              elif type=="string" then . else "" end ] | join("\n\n"))
            else "" end );
      [ .[] | select(type=="object") ] as $recs
      | ( [ $recs[]
            | select(.type=="user" or .type=="assistant")
            | { role: (if .type=="user" then "user" else "assistant" end), t: msgtext(.message),
                ts: (.timestamp // "") }
            | select(.t | nz)
            | select(.t | injected | not) ]
          # One reply is many records: the assistant emits a fresh record for every text block
          # between tool calls, and tool results come back as `user` records. On a real session
          # that is 1047 assistant and 681 user records for 15 actual turns, with runs of up to
          # 82 consecutive records of the same role. Since the tool calls in between are hidden,
          # rendering each record as its own turn shows one reply as a dozen frames and makes
          # the assistant look like it spoke far more often than it did. Merge the runs.
          | reduce .[] as $m ([];
              if (length > 0) and (.[-1].role == $m.role)
              # The run keeps the FIRST timestamp: a reply that took ten minutes of tool calls is
              # one turn, and it started when the assistant began, not when it finished.
              then .[0:-1] + [{ role: $m.role, t: (.[-1].t + "\n\n" + $m.t), ts: .[-1].ts }]
              else . + [$m] end)
          | . as $turns
          | ($turns | length) as $n
          | ( if $more == 1
              then "*… earlier turns are outside the preview window — ctrl-o reads further back*\n"
              else empty end ),
            ( range(0; $n)
              | . as $i
              | ($turns[$i] | when(if $i == 0 then null else $turns[$i-1].ts end)) as $w
              | turnblock($turns[$i].role + (if $w == "" then "" else "  " + $w end);
                          ($turns[$i].t | clip($i == $n - 1))) ) )'

    # Whether anything fell outside the record window, without reading the file: ask for one
    # more record than we render and see if it comes back. tail reads from the end, so this
    # costs nothing even on an 84MB transcript.
    set -l more 0
    test (tail -n (math $lines + 1) "$path" | wc -l | string trim) -gt $lines; and set more 1

    _claude_records_jq "$path" $lines \
        --arg injected_re (_claude_injected_re) --argjson cap $cap --argjson think $think \
        --argjson more $more "$prog"
end
