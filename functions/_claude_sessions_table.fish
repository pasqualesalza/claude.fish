# Extracted from ccri so fzf can rebuild the list in place with reload() — a bind
# runs an external command, so it cannot see ccri's locals. It is also the seam
# where a compiled parser could later replace the jq pipeline without the UI
# noticing: the contract is just "NUL-separated records on stdout, most-recent first".
#
# Records are NUL-separated, not newline-separated, because in the default `roomy`
# layout one record spans two rendered lines. Callers read them with
# `(_claude_sessions_table | string split0)` and hand them to fzf with --read0.
function _claude_sessions_table --description "Emit the fzf picker table: display<NUL-record>id<TAB>path<TAB>cwd"
    argparse a/all t/trash -- $argv 2>/dev/null; or return 1

    set -l rows
    if set -q _flag_trash
        # The trash mirrors the projects layout (<enc>/<id>.jsonl), so listing it is
        # the same parse pointed at a different root.
        set -l troot (_claude_trash_root)
        test -d "$troot"; or return 0
        set -lx CLAUDE_FISH_PROJECTS_ROOT "$troot"
        set rows (_claude_sessions --all)
    else if set -q _flag_all
        set rows (_claude_sessions --all)
    else
        set rows (_claude_sessions)
    end
    test (count $rows) -gt 0; or return 0

    # Liveness and pins are read once per build; both are a handful of small files.
    set -l live_ids
    set -l live_st
    if not set -q _flag_trash
        for l in (_claude_live_sessions)
            set -l lp (string split \t -- $l)
            set -a live_ids $lp[1]
            set -a live_st $lp[2]
        end
    end
    set -l pins
    not set -q _flag_trash; and set pins (_claude_pins)

    # One date(1) for the whole build, not one per row.
    set -l now (date +%s)

    set -l roomy 1
    if set -q claude_fish_layout; and test "$claude_fish_layout" = compact
        set roomy 0
    end

    set -l dim (set_color -d)
    set -l rst (set_color normal)
    set -l bold (set_color -o)
    set -l c_pin (set_color yellow)
    set -l c_busy (set_color green)
    set -l c_idle (set_color cyan)

    # Pinned rows are collected separately and emitted first: with an empty query
    # fzf preserves input order, so this is the whole pinning mechanism.
    set -l pinned
    set -l plain

    for r in $rows
        set -l p (string split \t -- $r)
        set -l id $p[1]
        set -l title $p[2]
        set -l cwd $p[3]
        set -l path $p[4]
        set -l mtime $p[5]
        set -l body $p[6]

        set -l is_pinned 0
        contains -- $id $pins; and set is_pinned 1

        set -l mark ' '
        test $is_pinned -eq 1; and set mark "$c_pin★$rst"

        # ● busy / ○ idle: the session is open in another terminal right now.
        set -l livemark ' '
        if set -l i (contains -i -- $id $live_ids)
            if test "$live_st[$i]" = busy
                set livemark "$c_busy●$rst"
            else
                set livemark "$c_idle○$rst"
            end
        end

        set -l age (_claude_reltime $mtime $now)
        set -l short (string sub -l 8 -- $id)
        set -l where (string replace -- "$HOME" '~' "$cwd")

        set -l disp
        if test $roomy -eq 1
            # One record, two rendered lines: title, then dimmed metadata. `string
            # collect` is load-bearing — without it fish splits the command
            # substitution on the newline and every session becomes TWO entries.
            set -l meta "$age · $short"
            test -n "$where"; and set meta "$meta · $where"
            test -n "$body"; and set meta "$meta · $body"
            set disp (printf '%s%s %s%s\n   %s%s%s' \
                "$mark" "$livemark" "$bold" "$title" "$dim" "$meta" "$rst" | string collect)
        else
            set disp "$mark$livemark$dim$age$rst $title $dim$short$rst"
            if set -q _flag_all; or set -q _flag_trash
                test -n "$where"; and set disp "$disp $dim· $where$rst"
            end
            test -n "$body"; and set disp "$disp $dim│ $body$rst"
        end

        set -l line (printf '%s\t%s\t%s\t%s' "$disp" "$id" "$path" "$cwd" | string collect)
        if test $is_pinned -eq 1
            set -a pinned $line
        else
            set -a plain $line
        end
    end

    test (count $pinned) -gt 0; and printf '%s\0' $pinned
    test (count $plain) -gt 0; and printf '%s\0' $plain
    return 0
end
