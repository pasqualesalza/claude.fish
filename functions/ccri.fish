function ccri --description "Interactively pick and resume a Claude Code session (fzf)"
    argparse a/all h/help -- $argv; or return 1
    if set -q _flag_help
        echo "ccri [--all] [query]   fuzzy-pick a Claude session and resume it"
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
        echo "ccri: no Claude sessions found" >&2
        return 1
    end

    # Build the fzf table: display<TAB>id<TAB>path<TAB>cwd. Only the display
    # column is shown and searched (--with-nth 1); it carries the title plus a
    # dimmed transcript snippet so fuzzy search reaches into the conversation.
    set -l dim (set_color -d)
    set -l rst (set_color normal)
    set -l input
    for r in $rows
        set -l p (string split \t -- $r)
        set -l id $p[1]
        set -l title $p[2]
        set -l cwd $p[3]
        set -l path $p[4]
        set -l body $p[5]

        set -l disp $title
        if set -q _flag_all; and test -n "$cwd"
            set disp "$title $dim· "(string replace -- "$HOME" '~' "$cwd")"$rst"
        end
        test -n "$body"; and set disp "$disp $dim│ $body$rst"

        set -a input (printf '%s\t%s\t%s\t%s' "$disp" "$id" "$path" "$cwd")
    end

    # Reuse fzf.fish's wrapper when present (consistent look + SHELL=fish for the
    # preview); otherwise fall back to plain fzf and set SHELL ourselves so the
    # autoloaded preview function resolves.
    set -l picker fzf
    if functions -q _fzf_wrapper
        set picker _fzf_wrapper
    else
        set -lx SHELL (command -s fish)
    end

    set -l selected (printf '%s\n' $input | $picker \
        --ansi --delimiter \t --with-nth 1 --no-hscroll \
        --query "$query" \
        --prompt 'claude resume> ' \
        --preview '_claude_session_preview {3} {q}' \
        --preview-window 'right:55%:wrap' \
        --bind 'ctrl-/:change-preview-window(hidden|right,55%,wrap)' \
        --header 'enter: resume · ctrl-/: toggle preview')
    or return

    test -n "$selected"; or return
    set -l s (string split \t -- $selected)
    set -l id $s[2]
    set -l scwd $s[4]
    if test -n "$scwd"; and test "$scwd" != "$PWD"
        cd "$scwd"; or return 1
    end
    claude --resume $id
end
