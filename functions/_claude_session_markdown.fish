# The transcript as plain markdown, for a real renderer (mdcat) to typeset.
#
# This splits the job the way the hand-rolled path cannot: we decide the *structure*
# (which turns, in what order, how the role is marked) and the renderer decides the
# *typography* (wrapping at the right width, tables, nested lists, syntax-highlighted
# code). Roles are `##` headings because mdcat draws those as a coloured rule + name.
#
# It duplicates the record-extraction jq in _claude_session_preview. That is a real cost,
# accepted deliberately: unifying them would mean rewriting the working ANSI fallback to
# consume markdown instead of records, and the fallback is what keeps the plugin working
# with no dependency at all.
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

    # How a turn is marked. This is the real styling lever: mdcat is not themeable per
    # element, but it draws each markdown construct differently, so choosing the construct
    # chooses the look. An unrecognised value falls through to `heading`.
    #   heading  ## user   -> ━━ user            (default)
    #   rule     --- + ##   -> ══════ full-width rule, then ━━ user
    #   quiet    ### user  -> ── user             (lighter)
    #   quote    > quote    -> │ gutter that survives wrapping, but italic throughout
    set -l turns heading
    if set -q claude_fish_turns; and test -n "$claude_fish_turns"
        set turns $claude_fish_turns
    end

    set -l id (string replace -r '\.jsonl$' '' -- (path basename "$path"))
    set -l mtime (stat -f '%m' "$path" 2>/dev/null)
    test -n "$mtime"; or set mtime (stat -c '%Y' "$path" 2>/dev/null)
    set -l size (du -h "$path" 2>/dev/null | cut -f1 | string trim)
    set -l facts
    test -n "$size"; and set -a facts "$size"
    test -n "$mtime"; and set -a facts (string trim -- (_claude_reltime $mtime))
    for l in (_claude_live_sessions)
        set -l lp (string split \t -- $l)
        test "$lp[1]" = "$id"; and set -a facts "open now ($lp[2])"
    end
    set -a facts (string sub -l 8 -- $id)

    # tool_use / tool_result blocks carry neither .text nor .thinking, so they drop out
    # here — the same noise policy cchb and ccresume adopt. Thinking is held back too,
    # except in read mode.
    set -l prog '
      def nz: . != null and . != "";
      def turnblock($role; $text):
          if   $turns == "rule"  then "\n---\n\n## " + $role + "\n\n" + $text
          elif $turns == "quiet" then "\n### " + $role + "\n\n" + $text
          elif $turns == "quote" then "\n> **" + $role + "**\n>\n> " + ($text | gsub("\n"; "\n> "))
          else "\n## " + $role + "\n\n" + $text end;
      def msgtext(m):
        (m.content) as $c
        | ( if   ($c|type) == "string" then $c
            elif ($c|type) == "array"  then
              ([ $c[0:80][] | if type=="object" then (.text // (if $think == 1 then .thinking else null end) // "")
                              elif type=="string" then . else "" end ] | join("\n\n"))
            else "" end );
      [ .[] | select(type=="object") ] as $recs
      | ( [ $recs[] | select(.type=="custom-title") | .customTitle ] | last ) as $custom
      | ( [ $recs[] | select(.type=="ai-title") | .aiTitle ] | last ) as $ai
      | ( [ $recs[] | select(.type=="agent-name") | .agentName ] | last ) as $agent
      | ( [ $recs[] | select(.type=="last-prompt") | .lastPrompt ] | last ) as $last
      | ( [ $recs[] | select(.type=="user" and ((.isMeta // false) | not)) | msgtext(.message) | select(nz) ] | first ) as $firstuser
      | ( [ $recs[] | .cwd // empty ] | last ) as $cwd
      | ( [ $recs[] | .gitBranch // empty | select(nz) ] | last ) as $branch
      | ( [ $recs[] | select(.type=="assistant") | .message.model // empty | select(nz) ] | last ) as $model
      | ( if ($custom | nz) then $custom
          elif ($ai | nz) then $ai
          elif ($agent | nz) then $agent
          elif ($firstuser | nz) then ($firstuser | .[0:120])
          else "(untitled)" end ) as $title
      | ( [ (($cwd // "") | sub("^" + $home; "~")), $branch, $model ]
          | map(select(nz)) | map("`" + . + "`") | join(" · ") ) as $where
      | ( "# " + ($title | gsub("[\n\r]+"; " "))
          + (if ($where | nz) then "\n\n" + $where else "" end)
          + "\n\n`" + $facts + "`"
          + (if ($last | nz)
             then "\n\n> ↩ " + ($last | .[0:500] | gsub("[ \t\n\r]+"; " ") | .[0:240])
             else "" end) ),
        ( $recs[]
          | select(.type=="user" or .type=="assistant")
          | msgtext(.message) as $t
          | select($t | nz)
          | turnblock((if .type=="user" then "user" else "assistant" end); ($t | .[0:$cap])) )'

    _claude_session_records "$path" $lines \
        | jq -rs --arg facts (string join ' · ' $facts) --arg home "$HOME" \
        --arg turns "$turns" --argjson cap $cap --argjson think $think "$prog" 2>/dev/null
end
