function _claude_sessions --description "Emit Claude Code sessions as TSV: id<TAB>title<TAB>cwd<TAB>path<TAB>body, most-recent first"
    argparse a/all -- $argv 2>/dev/null; or return 1

    # Project root is overridable so tests can point it at fixtures.
    set -l root "$HOME/.claude/projects"
    set -q CLAUDE_FISH_PROJECTS_ROOT; and set root $CLAUDE_FISH_PROJECTS_ROOT
    test -d "$root"; or return 0
    type -q jq; or return 0

    # Which project dirs to scan. Default: just the current project, encoded the
    # way Claude Code does it (every non-alphanumeric byte -> '-').
    set -l dirs
    if set -q _flag_all
        for d in "$root"/*/
            test -d "$d"; and set -a dirs "$d"
        end
    else
        set -l enc (string replace -ra '[^a-zA-Z0-9]' '-' -- "$PWD")
        test -d "$root/$enc"; and set dirs "$root/$enc"
    end
    test (count $dirs) -gt 0; or return 0

    # jq: pull a title, the session cwd, and a capped transcript body out of one
    # .jsonl. Mirrors Claude Code's own picker: drop sidechains (subagent
    # transcripts) and empty shells. Title priority: summary -> first real user
    # prompt -> "(untitled)".
    set -l prog '
      def msgtext(m):
        (m.content) as $c
        | if   ($c|type) == "string" then $c
          elif ($c|type) == "array"  then
            ([ $c[] | if type=="object" then (.text // .thinking // "")
                      elif type=="string" then . else "" end ] | join(" "))
          else "" end;
      def oneline: gsub("[\t\r\n]+"; " ") | gsub("  +"; " ") | gsub("^ +| +$"; "");
      (map(.isSidechain // false) | any) as $side
      | [ .[] | select(.type=="user" or .type=="assistant") ] as $msgs
      | ($msgs | length) as $n
      | ( [ .[] | select(.type=="summary") | .summary ] | last ) as $sum
      | ( [ $msgs[] | select(.type=="user" and ((.isMeta // false) | not)) | msgtext(.message) ]
          | map(select(. != null and . != "")) | first ) as $firstuser
      | ( [ .[] | .cwd // empty ] | last ) as $cwd
      | ( [ $msgs[] | msgtext(.message) ] | map(select(. != null and . != "")) | join(" ") | .[0:2000] ) as $body
      | if ($side or $n == 0) then empty
        else [ (($sum // $firstuser // "(untitled)") | oneline | .[0:120]),
               (($cwd // "") | oneline),
               ($body | oneline) ] | @tsv
        end'

    set -l lines
    for d in $dirs
        for f in "$d"/*.jsonl
            test -f "$f"; or continue
            set -l id (string replace -r '\.jsonl$' '' -- (basename "$f"))
            string match -qr '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -- "$id"; or continue

            set -l meta (jq -rs "$prog" "$f" 2>/dev/null)
            test -n "$meta"; or continue
            set -l parts (string split \t -- $meta)
            set -l title $parts[1]
            set -l mcwd $parts[2]
            set -l body $parts[3]

            set -l mtime (stat -f %m "$f" 2>/dev/null; or stat -c %Y "$f" 2>/dev/null; or echo 0)
            set -a lines (printf '%s\t%s\t%s\t%s\t%s\t%s' "$mtime" "$id" "$title" "$mcwd" "$f" "$body")
        end
    end
    test (count $lines) -gt 0; or return 0

    # Sort by mtime desc, then drop the mtime column.
    printf '%s\n' $lines | sort -t \t -k1,1 -rn | cut -f2-
end
