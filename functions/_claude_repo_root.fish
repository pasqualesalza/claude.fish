# The main repository root for $PWD — the same answer from inside one of its worktrees.
#
# `git rev-parse --show-toplevel` is the obvious call and the wrong one here: inside a worktree it
# returns the WORKTREE root, which would scope the picker to the directory you are already in. The
# common git dir belongs to the main checkout (a worktree's `.git` is a file pointing at it), so
# its parent is the repo everything hangs off — and from the main checkout it is the same answer.
function _claude_repo_root --description "The main repository root for the current directory"
    set -l common (git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    if test -n "$common"
        set -l root (path dirname -- "$common")
        if test -d "$root"
            echo $root
            return 0
        end
    end
    # Older git without --path-format, or a layout where the git dir lives somewhere else: the
    # working tree root is still better than nothing.
    set -l top (git rev-parse --show-toplevel 2>/dev/null)
    if test -n "$top"
        echo $top
        return 0
    end
    return 1
end
