# Epoch seconds from a transcript timestamp (`2026-08-25T14:58:03.602Z`), or nothing.
#
# The input is UTC — the trailing Z — so it must be PARSED as UTC and only then formatted in
# local time by the caller; parsing it as local time shifts every stamp by the offset.
#
# GNU form first, BSD second, and the result is required to be digits. The lesson is the same one
# `stat` taught: `date -d` exists on macOS too and means something else entirely (it sets the
# kernel daylight-saving value), so a bare fallback chain cannot be trusted to fail cleanly —
# validating the output is what makes the probe safe on both.
function _claude_epoch --description "Epoch seconds from an ISO-8601 UTC timestamp"
    set -l iso (string replace -r '[.][0-9]+Z$' 'Z' -- "$argv[1]")
    test -n "$iso"; or return 1

    set -l e (date -u -d "$iso" +%s 2>/dev/null)
    if not string match -qr '^[0-9]+$' -- "$e"
        set e (date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$iso" +%s 2>/dev/null)
    end
    string match -qr '^[0-9]+$' -- "$e"; or return 1
    echo $e
end
