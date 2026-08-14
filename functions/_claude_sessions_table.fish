# Extracted from ccri so fzf can rebuild the list in place with reload() — a bind runs an
# external command, so it cannot see ccri's locals. It is also the seam where a compiled
# parser could later replace the jq pipeline without the UI noticing: the contract is just
# "NUL-separated records on stdout, most-recent first".
#
# Records are NUL-separated, not newline-separated, because one record spans two rendered lines. Callers read them with
# `(_claude_sessions_table | string split0)` and hand them to fzf with --read0.
function _claude_sessions_table --description "Emit the fzf picker table: display<NUL-record>id<TAB>path<TAB>cwd"
    argparse a/all t/trash u/under= w/width= -- $argv 2>/dev/null; or return 1

    # Everything visible is budgeted to this width, so a row ends on purpose instead of being
    # sliced by the pane border. ccri measures it from $COLUMNS and passes it to both the
    # first build and the reload command, so the two always agree — fzf's own FZF_COLUMNS is
    # still 0 until the UI has sized itself, which is exactly when the first build happens.
    set -l lw 60
    # `--width auto` measures the pane itself, which is what a reload after a window resize needs:
    # the first build cannot, since fzf reports 0 columns while it is still sizing the UI, so ccri
    # passes an explicit width there and `auto` afterwards.
    if test "$_flag_width" = auto
        set lw (_claude_list_width $FZF_COLUMNS)
    else if set -q _flag_width; and string match -qr '^[0-9]+$' -- "$_flag_width"; and test "$_flag_width" -gt 20
        set lw $_flag_width
    end

    # Where the transcript snippet starts. It has to be in the same field as everything else —
    # with --with-nth set, fzf searches the TRANSFORMED line, so a field the display hides is
    # not searchable either (measured: --nth 1,5 finds nothing) — and it has to be off-screen,
    # or it fills the right half of every row. So the visible part is padded out well past any
    # plausible pane width. Over-padding is the safe direction now that ccri passes
    # `--ellipsis ''`: the surplus is truncated silently, whereas under-padding lets the
    # snippet walk into view, which is exactly what it did.
    set -l hide (math "max($lw + 20, floor($lw * 1.5))")

    set -l rows
    if set -q _flag_trash
        # The trash mirrors the projects layout (<enc>/<id>.jsonl), so listing it is the same
        # parse pointed at a different root.
        set -l troot (_claude_trash_root)
        test -d "$troot"; or return 0
        set -lx CLAUDE_FISH_PROJECTS_ROOT "$troot"
        set rows (_claude_sessions --all)
    else if set -q _flag_under
        # A directory and everything below it: how a repo reaches into its own worktrees.
        set rows (_claude_sessions --under "$_flag_under")
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

    set -l dim (set_color -d)
    set -l rst (set_color normal)
    set -l bold (set_color -o)
    set -l c_pin (set_color yellow)
    set -l c_busy (set_color green)
    set -l c_idle (set_color cyan)

    # Pinned rows are collected separately and emitted first: with an empty query fzf
    # preserves input order, so this is the whole pinning mechanism.
    set -l pinned
    set -l plain

    for r in $rows
        set -l p (string split \t -- $r)
        set -l id $p[1]
        set -l title $p[2]
        set -l cwd $p[3]
        set -l path $p[4]
        set -l mtime $p[5]
        set -l branch $p[6]
        set -l body $p[7]

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

        set -l age (string trim -- (_claude_reltime $mtime $now))

        set -l disp
        set -l place (_claude_place "$cwd")
        set -l meta "$age · $place"
        # Skip the branch when it just repeats the worktree — `worktree-skill-layout-guardrails`
        # next to `.../skill-layout-guardrails` says the same thing twice and is exactly what
        # pushes a row over the edge. A `worktree-` prefix is the convention EnterWorktree uses.
        if test -n "$branch"
            set -l bare (string replace -r '^worktree-' '' -- $branch)
            if not string match -q "*$bare*" -- "$place"
                set meta "$meta · $branch"
            end
        end
        set -l line1 "$mark$livemark $bold"(_claude_fit "$title" (math $lw - 3))"$rst"
        set -l vis (_claude_fit "$meta" (math $lw - 3))
        set -l pad (string repeat -n (math "max(1, $hide - 3 - "(string length -- "$vis")")") ' ')
        # `string collect` is load-bearing: without it fish splits the command
        # substitution on the newline and every session shows up as TWO entries.
        set disp (printf '%s\n   %s%s%s%s%s' \
            "$line1" "$dim" "$vis" "$pad" "$body" "$rst" | string collect)

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
