# The trash MUST live on the same filesystem as the projects root: a same-fs move
# is a rename(2) — atomic, no copy, no partial file. A sibling directory of the
# projects root guarantees that (and stays out of Claude's own `projects/*` glob).
function _claude_trash_root --description "Path to claude.fish's trash for removed sessions"
    if set -q CLAUDE_FISH_TRASH_ROOT; and test -n "$CLAUDE_FISH_TRASH_ROOT"
        echo "$CLAUDE_FISH_TRASH_ROOT"
    else
        echo (path dirname (_claude_projects_root))/.claude-fish-trash
    end
end
