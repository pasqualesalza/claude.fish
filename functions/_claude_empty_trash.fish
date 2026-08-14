function _claude_empty_trash --description "Permanently delete every session in claude.fish's trash"
    set -l troot (_claude_trash_root)
    if not test -d "$troot"
        echo "ccr: the trash is empty"
        return 0
    end
    set -l files (find "$troot" -name '*.jsonl' -type f 2>/dev/null)
    if test (count $files) -eq 0
        echo "ccr: the trash is empty"
        return 0
    end

    echo "ccr: about to permanently delete "(count $files)" trashed session(s) from"
    echo "     "(string replace -- "$HOME" '~' "$troot")
    read -l -P 'type "yes" to confirm: ' answer
    if test "$answer" != yes
        echo "ccr: left the trash alone"
        return 1
    end
    # Scoped to the trash root we computed, never to a caller-supplied path.
    rm -rf "$troot"; or return 1
    echo "ccr: trash emptied"
end
