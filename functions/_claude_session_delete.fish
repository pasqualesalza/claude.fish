function _claude_session_delete --description "Move a Claude session transcript (and its sidecars) to claude.fish's trash"
    set -l src $argv[1]

    if test -z "$src"; or not test -f "$src"
        _claude_session_gripe "no such session file: $src"
        return 1
    end
    set -l id (string replace -r '\.jsonl$' '' -- (path basename "$src"))
    set -l short (string sub -l 8 -- $id)

    # Refuse while Claude is running this session. It appends with open→append→close
    # and never holds an fd, so pulling the file out from under a live process leaves
    # it to recreate a truncated stub at the old path — you end up with two half
    # transcripts instead of one.
    for l in (_claude_live_sessions)
        set -l lp (string split \t -- $l)
        if test "$lp[1]" = "$id"
            _claude_session_gripe "cannot trash $short: open in another terminal ($lp[2]) — quit it first"
            return 1
        end
    end

    set -l enc (path basename (path dirname "$src"))
    set -l troot (_claude_trash_root)
    set -l base (path dirname (_claude_projects_root))

    mkdir -p "$troot/$enc"; or return 1
    # Same filesystem by construction (sibling of the projects root), so this is a
    # rename(2): atomic, and nothing is ever half-copied.
    mv -f "$src" "$troot/$enc/$id.jsonl"; or return 1

    # Sidecar state Claude keys by session id. Leaving it behind orphans it.
    for s in session-env file-history
        if test -d "$base/$s/$id"
            mkdir -p "$troot/.sidecars/$id"
            mv -f "$base/$s/$id" "$troot/.sidecars/$id/$s" 2>/dev/null
        end
    end
    _claude_session_notice --set "trashed $short · ccri --trash to restore"
    return 0
end
