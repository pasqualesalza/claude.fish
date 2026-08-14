function ccri --description "Interactively pick and resume a Claude Code session (fzf)"
    argparse a/all t/trash h/help -- $argv; or return 1
    if set -q _flag_help
        echo "ccri [--all] [query]   fuzzy-pick a Claude session and resume it"
        echo "ccri --trash           browse trashed sessions; enter restores"
        echo ""
        echo "  enter   resume (restore, in --trash mode)"
        echo "  ctrl-x  move the session to the trash"
        echo "  ctrl-p  pin / unpin (pinned sessions sort first)"
        echo "  ctrl-o  read mode: full transcript, wider pane"
        echo "  ctrl-/  toggle the preview pane"
        echo ""
        echo "  set \$claude_fish_layout to 'compact' for one line per session"
        return 0
    end
    type -q jq; or begin
        echo "ccri: jq is required (e.g. brew install jq)" >&2
        return 1
    end
    set -l query (string join ' ' -- $argv)

    # fzf runs every preview and bind through `$SHELL -c`, and a child fish does NOT
    # inherit fish_function_path (it is global but unexported). So the child would
    # autoload only from its own path: fine for an installed plugin, broken when
    # running from a checkout — and broken *silently*, since a stale installed copy
    # of a function resolves instead of the one next to this file. Prepending our own
    # directory makes the binds resolve wherever the plugin actually lives.
    set -l fdir (path dirname (status filename))
    set -l pre "set -p fish_function_path "(string escape -- $fdir)"; "

    # The table is built by an external command, not inline, so fzf's reload() can
    # rebuild it in place after a delete or a pin toggle. Kept as a list to invoke
    # and as a string to hand to the binds.
    set -l build _claude_sessions_table
    if set -q _flag_trash
        set -a build --trash
    else if set -q _flag_all
        set -a build --all
    end
    set -l reload "$pre"(string join ' ' -- $build)

    # Records are NUL-separated because one entry spans two rendered lines.
    set -l rows ($build | string split0)
    if test (count $rows) -eq 0
        if set -q _flag_trash
            echo "ccri: the trash is empty" >&2
        else
            echo "ccri: no Claude sessions found" >&2
        end
        return 1
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

    # Actions report through the notice mailbox, and transform-header pulls it into the
    # header — so a refusal explains itself in place, with no modal "press any key" and
    # no keystroke to dismiss. Consuming the notice is what makes it fade on the next
    # action instead of sticking around. The permanent hints live in the footer.
    set -l hdrcmd "$pre"'_claude_picker_header'
    _claude_session_notice --consume >/dev/null # drop anything stale from a past run

    set -l ftrargs
    set -q _flag_trash; and set ftrargs --trash
    set -l footer (_claude_picker_footer $ftrargs)

    set -l prompt 'resume '
    set -l act_x "execute-silent($pre"'_claude_session_delete {3})+reload'"($reload)+transform-header($hdrcmd)"
    set -l act_p "execute-silent($pre"'_claude_session_pin {2})+reload'"($reload)+transform-header($hdrcmd)"
    if set -q _flag_trash
        set prompt 'restore '
        set act_x ignore
        set act_p ignore
    end

    # Reading happens INSIDE fzf, never in an external pager: a program launched from
    # execute() fights fzf for the terminal. glow's pager came out looking like an editor,
    # and less would not scroll — while fzf's own preview pane already scrolls (mouse wheel,
    # plus the shift/alt binds below). ctrl-o swaps the preview to the untruncated render
    # and widens the pane; ctrl-/ goes back.
    #
    # It widens to 78% rather than taking the screen: every comparable tool (cchb 35/65,
    # ccresume stacked, ccsession's fzf pane) keeps the list visible, and a full-screen
    # wall of text stops reading like a browser and starts reading like an editor.
    set -l prev_cmd '_claude_session_preview {3} {q}'
    set -l prev_full '_claude_session_preview --full {3}'

    # `wrap` is right for the hand-rolled renderer, which emits long lines and lets fzf fold
    # them. It is actively harmful with mdcat: mdcat already wraps prose to --columns, and the
    # only lines left over-long are CODE, which it deliberately does not reflow. Folding those
    # turns one 512-column line into eight ragged rows — on a real transcript that was 56
    # lines exploding into hundreds. Without wrap they are simply truncated at the edge.
    set -l wrap ':wrap'
    set -l wrap_read ',wrap'
    if type -q mdcat; and begin
            not set -q claude_fish_renderer; or test "$claude_fish_renderer" != ansi
        end
        set wrap ''
        set wrap_read ''
    end
    # transform-footer, not change-footer: same reason as the header — a literal takes
    # action syntax, so a ")" in the text would break parsing, while a command's stdout
    # is just text.
    set -l ftrcmd "$pre""_claude_picker_footer $ftrargs"
    set -l ftrcmd_read "$pre"'_claude_picker_footer --read'
    set -l act_o "change-preview($pre$prev_full)+change-preview-window(right,78%$wrap_read)+transform-footer($ftrcmd_read)"
    set -l act_slash "change-preview($pre$prev_cmd)+change-preview-window(right,55%$wrap_read|hidden)+transform-footer($ftrcmd)"

    # --accept-nth: with two-line entries the raw selection contains a newline, which
    # fish would split into two elements. Asking fzf for just the id/path/cwd fields
    # sidesteps that entirely.
    # --tiebreak=begin,index: default `length` breaks ties by line length, which is
    # noise here since every row carries a transcript snippet. Prefer matches near
    # the start of the line (the title), then input order — recency, pinned first.
    # --height=100%: fzf.fish's wrapper defaults to 90% to preserve scrollback; a
    # session browser wants the whole screen.
    set -l selected (printf '%s\0' $rows | $picker \
        --read0 --ansi --delimiter \t --with-nth 1 --accept-nth 2,3,4 --no-hscroll \
        --query "$query" \
        --height=100% --style=full --border-label ' claude sessions ' \
        --gap=1 --highlight-line --info=inline-right \
        --tiebreak 'begin,index' \
        --prompt "$prompt" \
        --preview "$pre$prev_cmd" \
        --preview-window "right:55%$wrap" \
        --bind "ctrl-/:$act_slash" \
        --bind "ctrl-x:$act_x" \
        --bind "ctrl-p:$act_p" \
        --bind "ctrl-o:$act_o" \
        --bind 'shift-up:preview-up,shift-down:preview-down' \
        --bind 'alt-up:preview-page-up,alt-down:preview-page-down' \
        --footer "$footer")
    or return

    test -n "$selected"; or return
    set -l s (string split \t -- $selected)
    set -l id $s[1]
    set -l spath $s[2]
    set -l scwd $s[3]

    if set -q _flag_trash
        _claude_session_restore "$spath"; or return 1
        echo "ccri: restored $id"
        return 0
    end

    if test -n "$scwd"; and test "$scwd" != "$PWD"
        cd "$scwd"; or return 1
    end
    # Record the resumed session so a later no-arg `ccr` in this shell follows it.
    set -g _claude_fish_last_session $id
    claude --resume $id
end
