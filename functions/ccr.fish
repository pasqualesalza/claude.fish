function ccr --description "Resume a Claude Code session — no args: latest here; <query>: best recency match"
    argparse a/all h/help -- $argv; or return 1
    if set -q _flag_help
        echo "ccr [--all] [query]   resume the latest (or best-matching) Claude session"
        return 0
    end
    set -l query (string join ' ' -- $argv)

    set -l rows
    if set -q _flag_all
        set rows (_claude_sessions --all)
    else
        set rows (_claude_sessions)
    end

    if test (count $rows) -eq 0
        echo "ccr: no Claude sessions found for "(set -q _flag_all; and echo "any project"; or string replace -- "$HOME" '~' "$PWD") >&2
        return 1
    end

    # rows come back most-recent-first as: id<TAB>title<TAB>cwd<TAB>path<TAB>body
    set -l chosen
    if test -z "$query"
        set chosen $rows[1]
    else
        # AND-match: pick the most-recent row whose title+body contains every term.
        set -l terms (string split -n ' ' -- (string lower -- "$query"))
        for r in $rows
            set -l p (string split \t -- $r)
            set -l hay (string lower -- "$p[2] $p[5]")
            set -l miss 0
            for t in $terms
                string match -q -- "*$t*" "$hay"; or begin
                    set miss 1
                    break
                end
            end
            if test $miss -eq 0
                set chosen $r
                break
            end
        end
    end

    # No heuristic match: degrade to the interactive picker, pre-filtered.
    if test -z "$chosen"
        echo "ccr: no match for '$query' — opening picker" >&2
        if set -q _flag_all
            ccri --all "$query"
        else
            ccri "$query"
        end
        return
    end

    set -l cp (string split \t -- $chosen)
    set -l id $cp[1]
    set -l scwd $cp[3]
    if test -n "$scwd"; and test "$scwd" != "$PWD"
        cd "$scwd"; or return 1
    end
    claude --resume $id
end
