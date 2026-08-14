# A short label for where a session lives. The full path costs 30-50 columns and pushes
# everything else off the row.
#
# For an ordinary checkout the basename is enough: `~/Projects/infrastructure` is
# `infrastructure`, and keeping the parent would only add a generic `Projects/`.
#
# Worktrees are the case that needs two names, because the interesting part is *which* worktree
# of *which* repo — and the basename alone would be the worktree name with no repo, or worse,
# some deep subdirectory inside it (`…/plugins/ask-web/mcp` reads as just `mcp`). So when the
# path runs through `.claude/worktrees/<name>`, the label is `<repo>/<worktree>` and everything
# below the worktree is dropped.
function _claude_place --description "Short where-it-lives label for a session's directory"
    set -l cwd $argv[1]
    test -n "$cwd"; or return 0

    set -l parts (string split -n / -- $cwd)
    set -l n (count $parts)

    # Find the `.claude/worktrees` segment, if any: the repo is the component before it and the
    # worktree the one after.
    for i in (seq $n)
        if test "$parts[$i]" = worktrees
            set -l claude_i (math $i - 1)
            set -l wt_i (math $i + 1)
            if test $claude_i -ge 2; and test "$parts[$claude_i]" = .claude; and test $wt_i -le $n
                set -l repo_i (math $claude_i - 1)
                echo "$parts[$repo_i]/$parts[$wt_i]"
                return 0
            end
        end
    end

    echo $parts[$n]
end
