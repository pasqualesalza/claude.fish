function _claude_session_restore --description "Move a trashed Claude session back into the projects tree"
    set -l src $argv[1]

    if test -z "$src"; or not test -f "$src"
        _claude_session_gripe "no such trashed session: $src"
        return 1
    end
    set -l id (string replace -r '\.jsonl$' '' -- (path basename "$src"))
    set -l enc (path basename (path dirname "$src"))
    set -l troot (_claude_trash_root)
    set -l proot (_claude_projects_root)
    set -l base (path dirname "$proot")

    if test -e "$proot/$enc/$id.jsonl"
        _claude_session_gripe (string sub -l 8 -- $id)" already exists — refusing to overwrite"
        return 1
    end

    mkdir -p "$proot/$enc"; or return 1
    mv -f "$src" "$proot/$enc/$id.jsonl"; or return 1

    for s in session-env file-history
        if test -d "$troot/.sidecars/$id/$s"
            mkdir -p "$base/$s"
            mv -f "$troot/.sidecars/$id/$s" "$base/$s/$id" 2>/dev/null
        end
    end
    rmdir "$troot/.sidecars/$id" 2>/dev/null
    return 0
end
