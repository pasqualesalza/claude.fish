# Fixed 4-char output so the age stays a real column in the picker.
#
# `--date` appends the calendar date once the counter stops being precise — past a week, `13d`
# tells you roughly how long ago and `24 Jul` tells you which day, and only the pair answers
# both. Below a week the date adds nothing and is not paid for. Opt-in because the preview
# header, which also calls this, is already full to its last column.
function _claude_reltime --description "Format epoch seconds as a compact relative age (12m, 3h, 5d)"
    argparse d/date -- $argv 2>/dev/null; or return 1
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
        # A week is where "9d" stops being a date you can place in your week.
        if set -q _flag_date; and test $d -ge 604800
            printf ' %s' (date -r $then '+%d %b' 2>/dev/null; or date -d "@$then" '+%d %b' 2>/dev/null)
        end
    else
        printf '%4s' '99d+'
    end
end
