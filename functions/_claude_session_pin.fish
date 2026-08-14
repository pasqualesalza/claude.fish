function _claude_session_pin --description "Toggle a session id in claude.fish's pin list"
    set -l id $argv[1]
    string match -qr '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -- "$id"; or return 1

    set -l dir (_claude_state_dir)
    set -l f "$dir/pins"
    set -l kept
    set -l found 0
    for p in (_claude_pins)
        if test "$p" = "$id"
            set found 1
        else
            set -a kept $p
        end
    end
    test $found -eq 0; and set -a kept $id

    mkdir -p "$dir"; or return 1
    # Write via a temp file in the same directory so a pin toggle can never leave
    # a half-written list behind.
    set -l tmp "$f".(random)
    if test (count $kept) -gt 0
        printf '%s\n' $kept >"$tmp"; or return 1
    else
        : >"$tmp"; or return 1
    end
    mv -f "$tmp" "$f"; or return 1

    set -l short (string sub -l 8 -- $id)
    if test $found -eq 0
        _claude_session_notice --set "pinned $short"
    else
        _claude_session_notice --set "unpinned $short"
    end
end
