function _claude_sessions --description "Emit Claude Code sessions as TSV: id<TAB>title<TAB>cwd<TAB>path<TAB>body, most-recent first"
    argparse a/all -- $argv 2>/dev/null; or return 1

    # Project root is overridable so tests can point it at fixtures.
    set -l root "$HOME/.claude/projects"
    set -q CLAUDE_FISH_PROJECTS_ROOT; and set root $CLAUDE_FISH_PROJECTS_ROOT
    test -d "$root"; or return 0
    type -q jq; or return 0

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

    # Candidate session files (UUID-named .jsonl) — builtins only, no subprocess.
    set -l files
    for d in $dirs
        for f in "$d"/*.jsonl
            test -f "$f"; or continue
            string match -qr '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jsonl$' -- "$f"; or continue
            set -a files "$f"
        end
    end
    test (count $files) -gt 0; or return 0

    # Keep only the most-recent N by mtime so --all over hundreds of sessions
    # stays fast. One bulk stat (BSD or GNU), then parse just the top slice.
    set -l limit 60
    set -q CLAUDE_FISH_LIMIT; and set limit $CLAUDE_FISH_LIMIT
    set -l recent
    if stat -f '%m' $files[1] >/dev/null 2>&1
        set recent (stat -f '%m %N' $files)
    else
        set recent (stat -c '%Y %n' $files)
    end
    set -l top (printf '%s\n' $recent | sort -rn | head -n $limit | string replace -r '^[0-9]+ ' '')
    test (count $top) -gt 0; or return 0

    # jq: title, session cwd, capped transcript body. Drops sidechains and empty
    # shells (mirrors Claude Code's own picker). The .[0:N] slices are NOT
    # cosmetic — they cap every string BEFORE the `oneline` gsub, which otherwise
    # goes quadratic on huge pasted-context messages (one real file took 44s
    # without them). Keep the caps.
    set -lx _ccf_prog '
      def msgtext(m):
        (m.content) as $c
        | ( if   ($c|type) == "string" then $c
            elif ($c|type) == "array"  then
              ([ $c[0:60][] | if type=="object" then (.text // .thinking // "")
                              elif type=="string" then . else "" end ] | join(" "))
            else "" end ) | .[0:2000];
      def oneline: gsub("[\t\r\n]+"; " ") | gsub("  +"; " ") | gsub("^ +| +$"; "");
      (map(.isSidechain // false) | any) as $side
      | [ .[] | select(.type=="user" or .type=="assistant") ] as $msgs
      | ($msgs | length) as $n
      | ( [ .[] | select(.type=="custom-title") | .customTitle ] | last ) as $custom
      | ( [ .[] | select(.type=="ai-title") | .aiTitle ] | last ) as $ai
      | ( [ .[] | select(.type=="agent-name") | .agentName ] | last ) as $agent
      | ( [ $msgs[0:80][] | select(.type=="user" and ((.isMeta // false) | not)) | msgtext(.message) ]
          | map(select(. != null and . != "")) | first ) as $firstuser
      | ( [ .[] | .cwd // empty ] | last ) as $cwd
      | ( [ $msgs[0:80][] | msgtext(.message) ] | map(select(. != null and . != "")) | join(" ") | .[0:2000] ) as $body
      | if ($side or $n == 0) then empty
        else [ ( (if ($custom // "") != "" then "✎ " + $custom else ($ai // $agent // $firstuser // "(untitled)") end) | .[0:300] | oneline | .[0:120]),
               (($cwd // "") | .[0:300] | oneline),
               ($body | oneline) ] | @tsv
        end'

    # Parse the selected files in parallel (no -I → -P works on BSD/macOS too).
    # Emit mtime<TAB>id<TAB>title<TAB>cwd<TAB>path<TAB>body, sort by mtime, drop it.
    printf '%s\n' $top | xargs -P 8 -n 1 bash -c '
        f="$1"
        meta=$( { grep -aE "\"type\":\"(custom-title|ai-title|agent-name)\"" "$f"; head -n 200 "$f"; } | jq -rs "$_ccf_prog" 2>/dev/null ) || exit 0
        [ -n "$meta" ] || exit 0
        mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
        id="${f##*/}"; id="${id%.jsonl}"
        t=$(printf "%s" "$meta" | cut -f1)
        c=$(printf "%s" "$meta" | cut -f2)
        b=$(printf "%s" "$meta" | cut -f3-)
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$mtime" "$id" "$t" "$c" "$f" "$b"
    ' _ | sort -t \t -k1,1 -rn | cut -f2-
end
