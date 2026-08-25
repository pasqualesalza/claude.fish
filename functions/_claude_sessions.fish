function _claude_sessions --description "Emit Claude Code sessions as TSV: id<TAB>title<TAB>cwd<TAB>path<TAB>mtime<TAB>branch<TAB>body, most-recent first"
    argparse a/all u/under= -- $argv 2>/dev/null; or return 1
    # `--under <dir>` scopes to a directory AND everything below it, which is how a repo sees
    # the sessions of its own worktrees. It filters on the cwd field rather than on the encoded
    # directory name: encoding replaces every non-alphanumeric with `-`, so a prefix match there
    # cannot tell `claude.fish` from `claude-fish2`. The cwd is exact.
    # Both the given path and its symlink-resolved form, because the two can differ and the cwd
    # recorded in a transcript is whatever the shell's PWD was — a logical path, symlinks intact.
    # Resolving only would have made `--under` silently match nothing under a symlinked directory,
    # which on macOS includes anything below /tmp.
    set -l under
    if set -q _flag_under
        set under (string replace -r '/+$' '' -- "$_flag_under")
        set -l resolved (path resolve -- "$_flag_under")
        contains -- "$resolved" $under; or set -a under "$resolved"
        set _flag_all --all
    end

    # Project root is overridable so tests can point it at fixtures.
    set -l root (_claude_projects_root)
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
    if set -q CLAUDE_FISH_LIMIT; and string match -qr '^[1-9][0-9]*$' -- "$CLAUDE_FISH_LIMIT"
        set limit $CLAUDE_FISH_LIMIT
    end
    set -l recent
    # GNU first, BSD second, and the order is load-bearing: `stat -f` on GNU means "filesystem
    # status", so it prints a multi-line block ABOUT the file to stdout and only then exits
    # non-zero. Trying BSD first therefore poisons the output on Linux even though the call
    # "failed" — the `2>/dev/null` hides the complaint, not the block. BSD's `stat -c` is simply an
    # illegal option: nothing on stdout, so probing in this order is safe on both.
    if stat -c '%Y' $files[1] >/dev/null 2>&1
        set recent (stat -c '%Y %n' $files)
    else
        set recent (stat -f '%m %N' $files)
    end
    set -l top (printf '%s\n' $recent | sort -rn | head -n $limit | string replace -r '^[0-9]+ ' '')
    test (count $top) -gt 0; or return 0

    # The input is three chunks: the head (title and the opening of the conversation), the title
    # records from anywhere in the file, and a TAIL — because jq takes the LAST cwd it sees and a
    # session can change directory. Reading only the head reported where a session *started*: on
    # a real transcript that named a worktree deleted since, while the session had moved back to
    # the main checkout and was perfectly resumable. `ccr` cd's into that field, so a stale value
    # is not cosmetic. The tail chunk comes last so its cwd wins, and a half-written final record
    # in it is handled by the retry below.
    # jq: title, session cwd, capped transcript body. The .[0:N] slices are NOT
    # cosmetic — they cap every string BEFORE the `oneline` gsub, which otherwise
    # goes quadratic on huge pasted-context messages (one real file took 44s
    # without them). Keep the caps. Sessions with no non-sidechain main turns are
    # dropped. (Other C0/ESC bytes are stripped by `tr` in the worker below.)
    set -lx _ccf_injected (_claude_injected_re)
    set -lx _ccf_prog '
      def nz: . != null and . != "";
      def oneline: gsub("[\t\r\n]+"; " ") | gsub("  +"; " ") | gsub("^ +| +$"; "");
      def msgtext(m):
        (m.content) as $c
        | ( if   ($c|type) == "string" then $c
            elif ($c|type) == "array"  then
              ([ $c[0:60][] | if type=="object" then (.text // .thinking // "")
                              elif type=="string" then . else "" end ] | join(" "))
            else "" end ) | .[0:2000];
      [ .[] | select((.type=="user" or .type=="assistant") and ((.isSidechain // false) | not)) ] as $msgs
      | ($msgs | length) as $n
      | ( [ .[] | select(.type=="custom-title") | .customTitle | select(nz) ] | last ) as $custom
      | ( [ .[] | select(.type=="ai-title") | .aiTitle | select(nz) ] | last ) as $ai
      | ( [ .[] | select(.type=="agent-name") | .agentName | select(nz) ] | last ) as $agent
      | ( [ $msgs[0:80][] | select(.type=="user" and ((.isMeta // false) | not))
            | msgtext(.message) | select(nz)
            # Skip the machinery Claude Code injects as user turns. A session started with a
            # slash command carries the command XML as its first user message, so untitled
            # sessions were listed as "<command-name>/clear</command-name> …". They arrive NOT
            # flagged isMeta, so that field cannot separate them from a real prompt.
            # (No apostrophes in here: this jq program is a single-quoted fish string, and one
            # stray quote ends it and takes the whole function definition with it.)
            | select(test($injected_re) | not) ]
          | first ) as $firstuser
      | ( [ .[] | .cwd // empty ] | last ) as $cwd
      | ( [ .[] | .gitBranch // empty | select(nz) ] | last ) as $branch
      | ( [ $msgs[0:80][] | msgtext(.message) ] | map(select(nz)) | join(" ") | .[0:2000] ) as $body
      | if $n == 0 then empty
        else [ ( (if ($custom | nz) then "✎ " + $custom
                  elif ($ai | nz) then $ai
                  elif ($agent | nz) then $agent
                  elif ($firstuser | nz) then $firstuser
                  else "(untitled)" end) | .[0:300] | oneline | .[0:120]),
               (($cwd // "") | .[0:300] | oneline),
               (($branch // "") | .[0:120] | oneline),
               ($body | oneline) ] | @tsv
        end'

    # Parse selected files in parallel. NUL-delimited input (paths with spaces),
    # head before grep so the LATEST title record wins, `tr` strips stray C0/ESC
    # bytes, and each worker writes to its own temp file (no shared-pipe
    # interleaving above PIPE_BUF). Then merge, sort by mtime desc, drop mtime.
    set -lx CCF_TMPD (mktemp -d)
    printf '%s\0' $top | xargs -0 -P 8 -n 1 bash -c '
        f="$1"
        # Three chunks go to jq: the head window (title and the opening of the conversation), the
        # title records from anywhere in the file, and a TAIL — jq takes the LAST cwd it sees, and a
        # session that moved after record 200 would otherwise be listed against where it started.
        #
        # The tail is added only when the file is actually longer than the head window: on a short
        # transcript the two windows overlap, which duplicated the body and spent its search cap
        # twice. The test for "longer than 200 lines" reads AT MOST 201 of them — `tail -n +201`
        # and `wc -l` both read from the start instead, and on this machine that took the list
        # build from 594ms to 3243ms.
        long=0
        [ "$(head -n 201 "$f" | wc -l)" -gt 200 ] && long=1
        # $1 says which window may end in half a record: 0 none, 1 the head, 2 the tail. Claude
        # appends while we read, so a young transcript can break in the head and a long one in the
        # tail; jq -s aborts on the first parse error and the session would vanish from the list
        # exactly while you are working in it.
        chunks() {
          if [ "$1" = 1 ]; then head -n 200 "$f" | sed "\$d"; else head -n 200 "$f"; fi
          grep -aE "\"type\":\"(custom-title|ai-title|agent-name)\"" "$f"
          [ "$long" = 1 ] || return 0
          if [ "$1" = 2 ]; then tail -n 50 "$f" | sed "\$d"; else tail -n 50 "$f"; fi
        }
        parse() {
          chunks "$1" | jq -rs --arg injected_re "$_ccf_injected" "$_ccf_prog" 2>/dev/null \
            | tr -d "\000-\010\013-\037"
        }
        meta=$(parse 0) || exit 0
        if [ -z "$meta" ]; then
          if [ "$long" = 1 ]; then meta=$(parse 2); else meta=$(parse 1); fi
        fi
        [ -n "$meta" ] || exit 0
        # GNU first (see above), and then insist on digits: whichever stat ran, anything that is
        # not a plain number is junk, and junk here becomes extra rows in the picker — a multi-line
        # value made every line of it one.
        mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
        case "$mtime" in ""|*[!0-9]*) mtime=0 ;; esac
        id="${f##*/}"; id="${id%.jsonl}"
        t=$(printf "%s" "$meta" | cut -f1)
        c=$(printf "%s" "$meta" | cut -f2)
        r=$(printf "%s" "$meta" | cut -f3)
        b=$(printf "%s" "$meta" | cut -f4-)
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$mtime" "$id" "$t" "$c" "$f" "$r" "$b" > "$CCF_TMPD/$id"
    ' _
    # Sort by the leading mtime, then move it after `path` so the body stays the
    # last field. `oneline` has already stripped tabs from the body, so the fixed
    # field count holds.
    set -l rows (find "$CCF_TMPD" -type f -exec cat {} + 2>/dev/null | sort -t \t -k1,1 -rn \
        | awk -F '\t' -v OFS='\t' '{ print $2, $3, $4, $5, $1, $6, $7 }')
    rm -rf "$CCF_TMPD"
    if test (count $under) -gt 0
        for r in $rows
            set -l c (string split \t -- $r)[3]
            for u in $under
                if test "$c" = "$u"; or string match -q "$u/*" -- "$c"
                    echo $r
                    break
                end
            end
        end
    else
        test (count $rows) -gt 0; and printf '%s\n' $rows
    end
end
