# Where to look when the current folder has no sessions filed under it — or nothing, when there is
# nowhere sensible to widen to.
#
# A session is filed under the directory it was STARTED in, and Claude Code keeps writing there
# after the session moves; only a `<id>/tool-results/` sidecar follows the new cwd. So standing in
# a worktree, the folder you are working in can hold no transcript at all while the session you are
# actually in is filed one level up — and `ccr` answered "no Claude sessions found" there, which is
# the one place it is plainly wrong.
#
# Shared by ccr and ccri so the two cannot drift, and so the rule is tested once.
function _claude_widen_root --description "Directory to widen the session search to, if any"
    set -l root (_claude_repo_root); or return 1
    # Already there: widening would repeat the search that just came back empty. Compared on the
    # RESOLVED paths — git answers with symlinks resolved while $PWD keeps them, so anywhere below
    # a symlinked directory (on macOS, anything under /tmp) the two never matched and the widening
    # fired at the repository root itself.
    test "$root" = (path resolve -- "$PWD"); and return 1
    echo $root
end
