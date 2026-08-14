# The preview for `ccri --worktrees`: which sessions live in the selected worktree, and where it
# is. The titles arrive already collected in a hidden field of the row (joined by RS, U+241E) —
# re-reading the transcripts here would cost about a second on every cursor move.
function _claude_worktree_preview --description "Preview for the worktree picker: the sessions inside one worktree"
    set -l dir $argv[1]
    set -l joined (string join ' ' -- $argv[2..-1])

    set -l cols 80
    if set -q FZF_PREVIEW_COLUMNS; and test -n "$FZF_PREVIEW_COLUMNS"
        set cols $FZF_PREVIEW_COLUMNS
    end

    printf '\033[1m%s\033[0m\n' (_claude_fit (_claude_place "$dir") $cols)
    if test -d "$dir"
        printf '\033[2m%s\033[0m\n' (_claude_fit "$dir" $cols)
    else
        # The transcripts outlived the checkout. Say so here, where the decision is made.
        printf '\033[2m%s\033[0m\n' (_claude_fit "$dir" $cols)
        printf '\033[1;33m%s\033[0m\n' 'the worktree is gone — resuming cannot land in it'
    end
    printf '\033[2m%s\033[0m\n' (string repeat -n $cols ─)

    for t in (string split ␞ -- $joined)
        test -n "$t"; or continue
        printf '  %s\n' (_claude_fit "$t" (math $cols - 2))
    end
end
