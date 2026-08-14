function ccr --description "Resume a Claude Code session — no args: latest here; <query>: best recency match"
    argparse a/all r/repo h/help empty-trash -- $argv; or return 1
    if set -q _flag_help
        echo "ccr [--all] [query]   resume the latest (or best-matching) Claude session"
        echo "ccr --repo [query]    look in this repository AND its worktrees"
        echo "ccr --empty-trash     permanently delete everything in claude.fish's trash"
        return 0
    end
    type -q jq; or begin
        echo "ccr: jq is required (e.g. brew install jq)" >&2
        return 1
    end
    if set -q _flag_empty_trash
        _claude_empty_trash
        return $status
    end
    set -l query (string join ' ' -- $argv)

    set -l rows
    if set -q _flag_all
        set rows (_claude_sessions --all)
    else if set -q _flag_repo
        # This repository and its worktrees. Worth having on ccr more than anywhere: a session
        # started in the main checkout and continued in a worktree is filed under the directory it
        # was born in, so from the worktree a bare `ccr` found nothing at all.
        set -l root (_claude_repo_root)
        or begin
            echo "ccr: --repo needs a git repository (this is $PWD)" >&2
            return 1
        end
        set rows (_claude_sessions --under "$root")
    else
        set rows (_claude_sessions)
        # Nothing here? Widen to the repository — see _claude_widen_root for why the folder you
        # are working in can hold no transcript. Costs a full parse only when the fast path came
        # back empty.
        if test (count $rows) -eq 0
            set -l root (_claude_widen_root)
            if test -n "$root"
                set rows (_claude_sessions --under "$root")
                test (count $rows) -gt 0
                and echo "ccr: nothing filed under this folder — looking across "(_claude_place "$root")" and its worktrees" >&2
            end
        end
    end

    if test (count $rows) -eq 0
        echo "ccr: no Claude sessions found for "(set -q _flag_all; and echo "any project"; or string replace -- "$HOME" '~' "$PWD") >&2
        return 1
    end

    # rows come back most-recent-first as:
    # id<TAB>title<TAB>cwd<TAB>path<TAB>mtime<TAB>branch<TAB>body
    set -l chosen
    if test -z "$query"
        # No query: prefer the session THIS shell last resumed, so a terminal keeps
        # re-opening its own session even when another window's session in the same
        # project has since become the most-recently-modified. Fall back to newest.
        if set -q _claude_fish_last_session
            for r in $rows
                set -l p (string split \t -- $r)
                if test "$p[1]" = "$_claude_fish_last_session"
                    set chosen $r
                    break
                end
            end
        end
        test -z "$chosen"; and set chosen $rows[1]
    else
        # AND-match: pick the most-recent row whose title+body contains every term.
        set -l terms (string split -n ' ' -- (string lower -- "$query"))
        for r in $rows
            set -l p (string split \t -- $r)
            set -l hay (string lower -- "$p[2] $p[7]")
            set -l miss 0
            for t in $terms
                # Literal substring test: fish has no `string contains`, so match a
                # regex-escaped term (each metachar neutralised) unanchored.
                string match -rq -- (string escape --style=regex -- "$t") "$hay"; or begin
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
        else if set -q _flag_repo
            ccri --repo "$query"
        else
            ccri "$query"
        end
        return
    end

    set -l cp (string split \t -- $chosen)
    set -l id $cp[1]
    set -l scwd $cp[3]

    # Two Claude processes appending to one transcript interleave their records, so
    # warn before handing the same session to a second terminal.
    for l in (_claude_live_sessions)
        set -l lp (string split \t -- $l)
        if test "$lp[1]" = "$id"
            echo "ccr: warning — $id is already open elsewhere ($lp[2])" >&2
            break
        end
    end

    # Claude is launched in the session's directory and this shell is then put back where it was.
    # The cd is a means to an end — Claude has no flag for the working directory, `--add-dir` only
    # widens what tools may touch — and leaving the shell somewhere else afterwards is a side
    # effect nobody asked for, now more often a worktree buried under `.claude/worktrees` since
    # the recorded cwd is the CURRENT one rather than where the session started.
    #
    # Measured by driving fish through a pty: when a foreground child is KILLED by ctrl-c fish
    # skips the rest of the function, so a restore placed there would not run; when the child
    # catches SIGINT and exits on its own later — which is what Claude Code does, ctrl-c
    # interrupts the turn and not the app — the rest does run. So this holds in the normal path,
    # and if Claude is ever killed by a signal it degrades to the behaviour that shipped in
    # v0.2.2: the shell stays in the session's directory.
    set -l back $PWD
    if test -n "$scwd"; and test "$scwd" != "$PWD"
        # The recorded directory can be gone — a git worktree removed after the session ran. `cd`
        # would fail with its own bare error after you had already chosen the session, so say what
        # happened and hand over the one command that does not need the directory.
        if not test -d "$scwd"
            echo "ccr: the session's directory no longer exists — $scwd" >&2
            echo "    if it was a git worktree, recreate it, or resume from here with:" >&2
            echo "    claude --resume $id" >&2
            return 1
        end
        cd "$scwd"; or return 1
    end
    # Remember what this shell resumed so a later no-arg `ccr` re-opens it.
    set -g _claude_fish_last_session $id
    claude --resume $id
    set -l rc $status
    test "$PWD" = "$back"; or begin
        test -d "$back"; and cd "$back"
    end
    return $rc
end
