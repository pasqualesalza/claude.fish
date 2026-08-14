# One row per git worktree that has Claude sessions in it, for `ccri --worktrees`.
#
# Worktrees are where a lot of the work happens and the picker could not see across them: the
# default scope is the exact directory, `--all` is every project on the machine, and nothing sat
# in between. This view is the index — pick a worktree, then pick a session inside it.
#
# It reads the worktrees from the SESSIONS rather than from `git worktree list`, which is the
# whole point: a worktree that has been removed still has its transcripts, and those are exactly
# the ones you would otherwise never find again. Such a row is marked `gone`.
#
# Emits NUL-separated records of `visible<TAB>dir<TAB>titles`, like _claude_sessions_table, so
# ccri can read them with `string split0` and feed fzf `--read0`. The titles ride along in a
# hidden field, joined by RS (U+241E), so the preview can list what is inside a worktree without
# parsing every transcript again on each keystroke — that parse is a second of work.
function _claude_worktrees_table --description "Emit the git worktrees that have Claude sessions"
    argparse w/width= -- $argv 2>/dev/null; or return 1
    # `auto` measures the pane, for the reload that follows a window resize; the first build has
    # to be told, because fzf still reports 0 columns while it sizes the UI.
    set -l width 60
    if test "$_flag_width" = auto
        set width (_claude_list_width $FZF_COLUMNS)
    else if string match -qr '^[0-9]+$' -- "$_flag_width"
        set width $_flag_width
    end

    set -l rows (_claude_sessions --all)
    test (count $rows) -gt 0; or return 0

    # Group by worktree directory, keeping the newest mtime and the count. Fish has no hash, so
    # two parallel lists indexed together — the list is at most a few dozen entries.
    set -l dirs
    set -l counts
    set -l newest
    set -l titles
    for r in $rows
        set -l f (string split \t -- $r)
        string match -q '*/.claude/worktrees/*' -- "$f[3]"; or continue
        # A session can start below the worktree root (`.../worktrees/alpha/src`). Group and scope
        # by the root, otherwise one worktree appears as several rows and selecting `src` hides
        # sessions from its root and sibling directories.
        set -l dir (string replace -r '^(.*/\.claude/worktrees/[^/]+)(/.*)?$' '$1' -- "$f[3]")
        set -l i (contains -i -- "$dir" $dirs)
        if test -n "$i"
            set counts[$i] (math $counts[$i] + 1)
            test $f[5] -gt $newest[$i]; and set newest[$i] $f[5]
            set titles[$i] "$titles[$i]␞$f[2]"
        else
            set -a dirs "$dir"
            set -a counts 1
            set -a newest $f[5]
            set -a titles "$f[2]"
        end
    end
    test (count $dirs) -gt 0; or return 0

    set -l now (date +%s)
    for i in (seq (count $dirs))
        set -l age (string trim -- (_claude_reltime $newest[$i] $now))
        set -l n $counts[$i]
        set -l what session
        test $n -gt 1; and set what sessions
        # `gone` is the actionable part: the transcripts outlived the checkout, so resuming one
        # cannot land in its own directory.
        set -l state ''
        test -d "$dirs[$i]"; or set state ' · gone'
        # Padded to its column so the counts line up: the label is plain text at this point,
        # the colour goes on afterwards, so display width and string length agree.
        set -l lw (math $width - 24)
        set -l label (string pad -r -w $lw -- (_claude_fit (_claude_place "$dirs[$i]") $lw))
        set -l meta (_claude_fit "$age · $n $what$state" 22)
        printf '%s\t%s\t%s\0' (printf '\033[1m%s\033[0m \033[2m%s\033[0m' $label $meta) \
            "$dirs[$i]" "$titles[$i]"
    end
end
