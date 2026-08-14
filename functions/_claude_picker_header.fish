# Bound to transform-header, whose contract is just "stdout becomes the header" — no
# action syntax to escape, so a session title or a status like "(busy)" can never break
# it. Worst case the header is blank; it can never swallow a keybinding.
#
# This prints ONLY a pending notice, so the header line exists only when there is
# something to say. The permanent key hints live in fzf's --footer instead.
function _claude_picker_header --description "Header line for the ccri picker: a pending notice, or nothing"
    _claude_session_notice --consume
    return 0
end
