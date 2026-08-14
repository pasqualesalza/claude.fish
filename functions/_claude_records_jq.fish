# Run a jq program over a session's records, tolerating a half-written last line.
#
# Claude appends to a live transcript while we read it, so the final line can be half a record.
# `jq -s` aborts on the first parse error, which takes the WHOLE body with it: the pane would
# render its header and nothing else, and the session would drop out of the list — silently, and
# exactly for the sessions you look at most, the open ones.
#
# Tolerant parsing was measured and rejected: `jq -Rs '[splits("\n") | fromjson?]'` turns a 23ms
# parse into 846ms, 37 times slower, and this runs on every keystroke. So the normal path is
# unchanged and the repair is a retry that only ever runs after a failure — an empty result means
# either a broken record or a session with nothing to show, and both are cheap to ask twice.
function _claude_records_jq --description "jq over a session's records, tolerating a half-written last line"
    set -l path $argv[1]
    set -l lines $argv[2]
    set -l jqargv $argv[3..-1]

    # Streamed, not captured: routing the render through a fish variable to test it for
    # emptiness cost 220ms → 841ms on a 2.3MB session, because the whole output is copied twice.
    # jq's exit status answers the same question for free, and `-s` slurps before it emits
    # anything, so a parse failure can never leave half an answer behind.
    _claude_session_records "$path" $lines | jq -rs $jqargv 2>/dev/null
    if test $pipestatus[2] -ne 0
        _claude_session_records "$path" $lines | sed '$d' | jq -rs $jqargv 2>/dev/null
    end
end
