# Fixed 4-char output so the age stays a real column in the picker.
function _claude_reltime --description "Format epoch seconds as a compact relative age (12m, 3h, 5d)"
    set -l then $argv[1]
    # Callers in a loop pass `now` so we don't fork date(1) once per row — that alone
    # was 80ms of a 717ms list build.
    set -l now $argv[2]
    string match -qr '^[0-9]+$' -- "$now"; or set now (date +%s)
    string match -qr '^[0-9]+$' -- "$then"; or begin
        printf '%4s' ''
        return
    end
    set -l d (math $now - $then)
    test $d -lt 0; and set d 0
    if test $d -lt 60
        printf '%4s' now
    else if test $d -lt 3600
        printf '%3dm' (math "floor($d / 60)")
    else if test $d -lt 86400
        printf '%3dh' (math "floor($d / 3600)")
    else if test $d -lt 86400000
        printf '%3dd' (math "floor($d / 86400)")
    else
        printf '%4s' '99d+'
    end
end
