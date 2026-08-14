# Claude Code registers every running instance in ~/.claude/sessions/<pid>.json
# ({pid, sessionId, status, cwd, …}). That registry is the ONLY reliable liveness
# signal: Claude appends to a transcript with open→append→close, so no process
# ever holds an fd on the .jsonl and `lsof` sees nothing. Registry files outlive
# their process, hence the `kill -0` filter.
function _claude_live_sessions --description "Emit currently-running Claude sessions as TSV: id<TAB>status"
    set -l dir (path dirname (_claude_projects_root))/sessions
    if set -q CLAUDE_FISH_SESSIONS_DIR; and test -n "$CLAUDE_FISH_SESSIONS_DIR"
        set dir "$CLAUDE_FISH_SESSIONS_DIR"
    end
    test -d "$dir"; or return 0
    type -q jq; or return 0

    set -l files
    for f in "$dir"/*.json
        test -f "$f"; and set -a files "$f"
    end
    test (count $files) -gt 0; or return 0

    set -l prog '[(.pid // "" | tostring), (.sessionId // ""), (.status // "")] | @tsv'

    # Fast path: one jq for every registry file (~15ms instead of ~85ms for one fork
    # each). jq aborts on the first malformed file, so on failure fall back to parsing
    # them individually — a blanked-out liveness set would make the delete guard fail
    # OPEN, which is the one outcome we cannot accept for speed.
    set -l recs (jq -r "$prog" $files 2>/dev/null)
    if test $status -ne 0
        set recs
        for f in $files
            set -a recs (jq -r "$prog" "$f" 2>/dev/null)
        end
    end

    for rec in $recs
        test -n "$rec"; or continue
        set -l p (string split \t -- $rec)
        test (count $p) -ge 2; or continue
        test -n "$p[1]"; and test -n "$p[2]"; or continue
        string match -qr '^[0-9]+$' -- "$p[1]"; or continue
        kill -0 $p[1] 2>/dev/null; or continue
        printf '%s\t%s\n' "$p[2]" "$p[3]"
    end
end
