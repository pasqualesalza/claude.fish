# Complaints go two places: stderr for direct CLI use, and the picker's notice mailbox
# so fzf's header can show them (nothing an action writes to stdout or stderr survives
# the redraw that follows).
function _claude_session_gripe --description "Report a claude.fish refusal on stderr and to the picker header"
    set -l msg (string join ' ' -- $argv)
    echo "claude.fish: $msg" >&2
    # No emoji: the header is prose, and the list's ★/●/○ markers are the only glyphs
    # here — all monochrome and in the same width class as the ✎/↩/│ already in use.
    _claude_session_notice --set "$msg"
    return 0
end
