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

    set -l prog '
      def msgtext(m):
        (m.content) as $c
        | if   ($c|type) == "string" then $c
          elif ($c|type) == "array"  then
            ([ $c[] | if type=="object" then (.text // .thinking // "")
                      elif type=="string" then . else "" end ] | join(" "))
          else "" end;
      .[]
      | select(.type=="user" or .type=="assistant")
      | msgtext(.message) as $t
      | select($t != null and $t != "")
      | (if .type=="user" then "▸ user" else "▸ asst" end) + "\n" + ($t | .[0:4000]) + "\n"'

    if test -n "$query"
        set -l terms (string escape --style=regex (string split -n ' ' -- $query))
        set -l pat (string join '|' $terms)
        jq -rs "$prog" "$path" 2>/dev/null | grep -iE --color=always -- "$pat|\$"
    else
        jq -rs "$prog" "$path" 2>/dev/null
    end
end
