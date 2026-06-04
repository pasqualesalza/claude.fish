function _claude_session_preview --description "Render a Claude Code session transcript for the fzf preview pane"
    set -l path $argv[1]
    set -l query $argv[2]

    if test -z "$path"; or not test -f "$path"
        echo "(no session selected)"
        return
    end
    type -q jq; or begin
        echo "(jq not found)"
        return
    end

    # Recap header (title + "where you left off" = last prompt) then the most
    # recent messages, so you decide whether to resume at a glance. Title and
    # last-prompt lines are grepped from anywhere in the file; tail -n 400 bounds
    # the body to the recent end. ANSI is emitted as  escapes (fzf renders).
    set -l prog '
      def msgtext(m):
        (m.content) as $c
        | ( if   ($c|type) == "string" then $c
            elif ($c|type) == "array"  then
              ([ $c[0:80][] | if type=="object" then (.text // .thinking // "")
                              elif type=="string" then . else "" end ] | join("\n"))
            else "" end );
      ( [ .[] | select(.type=="custom-title") | .customTitle ] | last ) as $custom
      | ( [ .[] | select(.type=="ai-title") | .aiTitle ] | last ) as $ai
      | ( [ .[] | select(.type=="agent-name") | .agentName ] | last ) as $agent
      | ( [ .[] | select(.type=="last-prompt") | .lastPrompt ] | last ) as $last
      | ( if ($custom // "") != "" then "✎ " + $custom else ($ai // $agent // "(untitled)") end ) as $title
      | ( "[1m" + $title + "[0m"
          + (if ($last // "") != "" then "\n[2m↩ last: " + ($last | .[0:500] | gsub("[ \t\n\r]+"; " ") | .[0:240]) + "[0m" else "" end)
          + "\n[2m" + ("─" * 60) + "[0m" ),
        ( .[]
          | select(.type=="user" or .type=="assistant")
          | msgtext(.message) as $t
          | select($t != null and $t != "")
          | (if .type=="user" then "[1;32m▸ user[0m" else "[1;36m▸ assistant[0m" end)
            + "\n" + ($t | .[0:1200]) + (if ($t | length) > 1200 then "[2m …[0m" else "" end) )'

    if test -n "$query"
        set -l terms (string escape --style=regex (string split -n ' ' -- $query))
        set -l pat (string join '|' $terms)
        begin
            grep -aE '"type":"(custom-title|ai-title|agent-name|last-prompt)"' "$path"
            tail -n 400 "$path"
        end | jq -rs "$prog" 2>/dev/null | grep -iE --color=always -- "$pat|\$"
    else
        begin
            grep -aE '"type":"(custom-title|ai-title|agent-name|last-prompt)"' "$path"
            tail -n 400 "$path"
        end | jq -rs "$prog" 2>/dev/null
    end
end
