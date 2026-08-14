function _claude_projects_root --description "Path to the Claude Code projects root (overridable for tests)"
    if set -q CLAUDE_FISH_PROJECTS_ROOT; and test -n "$CLAUDE_FISH_PROJECTS_ROOT"
        echo "$CLAUDE_FISH_PROJECTS_ROOT"
    else
        echo "$HOME/.claude/projects"
    end
end
