# Hand-maintained completions for the `claude` CLI (Claude Code ships none).
# Lean by design: only the flags/subcommands actually in use — no recursive
# --help scraping, so nothing drifts silently when the CLI changes.

function _claude_complete_resume --description "Session ids + titles for `claude --resume`"
    _claude_sessions | while read -l line
        set -l p (string split \t -- $line)
        printf '%s\t%s\n' $p[1] $p[2]
    end
end

complete -c claude -f

# Flags
complete -c claude -s c -l continue -d 'Continue the most recent conversation'
complete -c claude -l resume -x -d 'Resume a session by id' -a '(_claude_complete_resume)'
complete -c claude -s p -l print -d 'Print response and exit (non-interactive)'
complete -c claude -l model -x -d 'Model to use' -a 'opus sonnet haiku'
complete -c claude -l permission-mode -x -d 'Permission mode' -a 'default acceptEdits plan bypassPermissions'
complete -c claude -l add-dir -r -d 'Add an extra working directory'
complete -c claude -l mcp-config -r -d 'Load MCP servers from a JSON file'
complete -c claude -l append-system-prompt -x -d 'Append text to the system prompt'
complete -c claude -s h -l help -d 'Show help'
complete -c claude -l version -d 'Show version'

# Subcommands
complete -c claude -n __fish_use_subcommand -a mcp -d 'Manage MCP servers'
complete -c claude -n __fish_use_subcommand -a config -d 'Manage configuration'
complete -c claude -n __fish_use_subcommand -a update -d 'Update Claude Code'
complete -c claude -n __fish_use_subcommand -a doctor -d 'Diagnose the installation'
