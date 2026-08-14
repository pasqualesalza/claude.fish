function _claude_pins --description "Emit pinned session ids, one per line"
    set -l f (_claude_state_dir)/pins
    test -f "$f"; or return 0
    # Tolerate hand-editing: skip blanks and anything that isn't a session id.
    for l in (string trim -- (cat "$f" 2>/dev/null))
        string match -qr '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -- "$l"; and echo "$l"
    end
end
