function _claude_state_dir --description "Path to claude.fish's own state directory (pins)"
    if set -q CLAUDE_FISH_STATE_DIR; and test -n "$CLAUDE_FISH_STATE_DIR"
        echo "$CLAUDE_FISH_STATE_DIR"
    else if set -q XDG_STATE_HOME; and test -n "$XDG_STATE_HOME"
        echo "$XDG_STATE_HOME/claude.fish"
    else
        echo "$HOME/.local/state/claude.fish"
    end
end
