function ccri --description "Interactively pick and resume a Claude Code session (fzf)"
    argparse a/all r/repo t/trash w/worktrees h/help -- $argv; or return 1
    if set -q _flag_help
        echo "ccri [--all] [query]   fuzzy-pick a Claude session and resume it"
        echo "ccri --trash           browse trashed sessions; enter restores"
        echo "ccri --repo            this repository AND its worktrees"
        echo "ccri --worktrees       pick a git worktree, then a session inside it"
        echo ""
        echo "  enter   resume (restore, in --trash mode)"
        echo "  ctrl-x  move the session to the trash"
        echo "  ctrl-p  pin / unpin (pinned sessions sort first)"
        echo "  ctrl-o  read the whole transcript full screen in your pager"
        echo "  ctrl-/  toggle the preview pane"
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
    # The list is 45% of the terminal; take off the borders --style=full draws. Measured here,
    # in the parent, and passed to both the first build and the reload command so the two agree
    # — fzf's own FZF_COLUMNS is still 0 while the UI is sizing itself, which is exactly when
    # the first build runs.
    # 12 off the 45%: the list border takes 2, the pointer takes 2, and the rest is slack.
    # Under-estimating is the safe direction — a row that ends early just has trailing spaces,
    # while over-estimating lets fzf cut a word in half at the border.
    set -l listw (_claude_list_width $COLUMNS)

    # Reuse fzf.fish's wrapper when present (consistent look + SHELL=fish for the
    # preview); otherwise fall back to plain fzf and set SHELL ourselves so the
    # autoloaded preview function resolves.
    set -l picker fzf
    if functions -q _fzf_wrapper
        set picker _fzf_wrapper
    else
        set -lx SHELL (command -s fish)
    end

    # `--worktrees` is an index in front of the picker: the default scope is the exact directory
    # and `--all` is every project on the machine, with nothing in between — while a worktree is
    # where much of the work actually happens, and from the main checkout the picker could not see
    # any of it. Pick a worktree here, then fall through to the ordinary picker scoped to it, so
    # the preview, ctrl-x, ctrl-p and the rest behave exactly as they always do.
    #
    # The worktrees come from the sessions, not from `git worktree list`: a removed worktree still
    # has its transcripts, and those are the ones you would otherwise never find again.
    set -l scope
    # `--repo` is the scope that was missing: the default is the exact directory, `--all` is every
    # project on the machine, and a repo with worktrees has its sessions spread across both. From
    # the main checkout of this very plugin the picker saw none of them, because a session is filed
    # under the directory it was born in.
    if set -q _flag_repo
        set scope (_claude_repo_root)
        or begin
            echo "ccri: --repo needs a git repository (this is $PWD)" >&2
            return 1
        end
    end
    if set -q _flag_worktrees
        set -l wrows (_claude_worktrees_table --width $listw | string split0)
        if test (count $wrows) -eq 0
            echo "ccri: no sessions in any worktree" >&2
            return 1
        end
        set scope (printf '%s\0' $wrows | $picker \
            --read0 --ansi --delimiter \t --with-nth 1 --accept-nth 2 --no-hscroll \
            --ellipsis '' \
            --height=100% --style=full --border-label ' claude worktrees ' \
            --highlight-line --info=inline-right \
            --tiebreak 'begin,index' \
            --prompt 'worktree ' \
            --preview "$pre"'_claude_worktree_preview {2} {3}' \
            --preview-window 'right:55%,wrap' \
            --bind "resize:reload($pre"'_claude_worktrees_table --width auto)' \
            --footer 'enter open · esc quit')
        # Backing out of a picker is not a failure. fzf exits 130 on esc/ctrl-c and 1 on no
        # match, and propagating those verbatim painted an error in the prompt every time you
        # looked and changed your mind. Anything else — 2 for an fzf error, 127 for a missing
        # fzf — is a failure and still propagates.
        set -l rc $status
        if test $rc -ne 0
            contains -- $rc 1 130; and return 0
            return $rc
        end
        test -n "$scope"; or return 0
    end

    set -l build _claude_sessions_table --width $listw
    if set -q _flag_trash
        set -a build --trash
    else if test -n "$scope"
        set -a build --under $scope
    else if set -q _flag_all
        set -a build --all
    end
    # The reload command asks for `auto` rather than carrying the width measured at startup,
    # because a resize leaves the ROWS stale. Measured on the real picker through a pty, resizing
    # 140 → 90: fzf re-runs the preview by itself (the turn frames follow, 70 columns to 43) but it
    # does not rebuild the list, so the rows kept their startup budget. With `resize:reload` the
    # width helper is called twice, 140 then 86; without it, once.
    set -l reload "$pre"(string join ' ' -- $build[1] --width auto $build[4..-1])

    # Records are NUL-separated because one entry spans two rendered lines.
    set -l rows ($build | string split0)
    # Same widening as ccr: a session is filed under the directory it was started in, so standing
    # in a worktree can show an empty picker while the session you are in is filed one level up.
    set -l widened
    if test (count $rows) -eq 0; and not set -q _flag_trash; and not set -q _flag_all; and test -z "$scope"
        set -l root (_claude_widen_root)
        if test -n "$root"
            set -a build --under $root
            set reload "$pre"(string join ' ' -- $build[1] --width auto $build[4..-1])
            set rows ($build | string split0)
            # The notice is set further down, AFTER the stale-notice consume: setting it here
            # meant that consume ate it before the header ever rendered.
            test (count $rows) -gt 0; and set widened (_claude_place "$root")
        end
    end
    if test (count $rows) -eq 0
        if set -q _flag_trash
            echo "ccri: the trash is empty" >&2
        else
            echo "ccri: no Claude sessions found" >&2
        end
        return 1
    end

    # Actions report through the notice mailbox, and transform-header pulls it into the
    # header — so a refusal explains itself in place, with no modal "press any key" and
    # no keystroke to dismiss. Consuming the notice is what makes it fade on the next
    # action instead of sticking around. The permanent hints live in the footer.
    set -l hdrcmd "$pre"'_claude_picker_header'
    _claude_session_notice --consume >/dev/null # drop anything stale from a past run
    test -n "$widened"
    and _claude_session_notice --set "nothing filed under this folder — showing $widened and its worktrees"

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

    # ctrl-o hands the WHOLE terminal to a pager rather than widening the pane, because reading
    # is a different job from glancing. fzf refuses a preview window over 99% — "window size too
    # large (max: 99%)" — which on a 140-column terminal is 132x38, while execute() suspends fzf
    # and the pager gets the full 140x40 with no chrome, plus / search, g/G and a percentage.
    #
    # The note that used to sit here said a program launched from execute() fights fzf for the
    # terminal and that less would not scroll. Both were wrong. Driven through a pty end to end:
    # ctrl-o paints the pager (+3.9KB), space scrolls it (+2.9KB), q redraws the picker (+10KB),
    # three alternate-screen switches in all — fzf restores the terminal on the way in and takes
    # it back on the way out, which is exactly what execute() is for.
    #
    # +G opens on the last message, the same place the preview pane lands.
    #
    # FZF_PREVIEW_COLUMNS is a preview-only variable, so inside an execute() the render would
    # quietly fall back to its 80-column default. FZF_COLUMNS is fzf's own and carries the
    # terminal width (measured 140 of 140), which is what the pager has to fill.
    #
    # Without less the pane is still the answer, at the 99% fzf allows; ctrl-/ goes back.
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

    # `~3` pins the three header lines _claude_session_head emits, so which session you are
    # looking at stays on screen while the transcript scrolls under it. The count has to be a
    # constant, which is why that header truncates each line instead of letting it wrap.
    #
    # `follow` is what lands the pane on the newest exchange, and it is the ONLY thing that
    # does. Measured, by reading fzf's own scroll indicator out of a pty on a 500-line preview:
    #
    #   follow            first visible line 466/500   the end, at the bottom
    #   +99999            500/500                      last line at the TOP, blank pane under it
    #   +99999-/1         500/500                      the -/1 buys nothing: fzf clamps LAST,
    #                                                  so arithmetic on a huge base never lands
    #   preview-bottom    4/500                        inert on start, load, result and focus
    #                     (identical to no binding at all — the event fires before the preview
    #                      content exists, so there is nothing yet to scroll)
    #
    # And scrolling back up STICKS: five preview-up keys moved it 466 → 461, and it was still
    # 461 a beat later. `follow` only re-pins to the bottom when the preview is regenerated —
    # which happens when you move to another session, and landing on its end is the point.
    set -l pin '~3,follow'
    # transform-footer, not change-footer: same reason as the header — a literal takes
    # action syntax, so a ")" in the text would break parsing, while a command's stdout
    # is just text.
    set -l ftrcmd "$pre""_claude_picker_footer $ftrargs"
    set -l ftrcmd_read "$pre"'_claude_picker_footer --read'
    #
    # `-S` chops a line at the right edge instead of folding it, and arrow keys pan. It is the same
    # call the pane already makes — `wrap` was measured out of the mdcat path because one 512-column
    # code line became eight ragged rows, 56 lines producing 118 extra rows on a real transcript —
    # and it is what keeps the frames intact if the window is resized mid-read: that text was
    # rendered for the width it had at launch, `less` cannot re-render our pipeline, so folding it
    # spills every frame rule onto a second row. `q` then `ctrl-o` re-renders at the new size.
    set -l act_o "execute($pre"'set -x FZF_PREVIEW_COLUMNS $FZF_COLUMNS; '"$prev_full | less -R -S +G)"
    if not type -q less
        set act_o "change-preview($pre$prev_full)+change-preview-window(right,99%$wrap_read,$pin)+transform-footer($ftrcmd_read)"
    end
    set -l act_slash "change-preview($pre$prev_cmd)+change-preview-window(right,55%$wrap_read,$pin|hidden)+transform-footer($ftrcmd)"

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
        --ellipsis '' \
        --query "$query" \
        --height=100% --style=full --border-label ' claude sessions ' \
        --gap=1 --highlight-line --info=inline-right \
        --tiebreak 'begin,index' \
        --prompt "$prompt" \
        --preview "$pre$prev_cmd" \
        --preview-window "right:55%$wrap,$pin" \
        --bind "ctrl-/:$act_slash" \
        --bind "ctrl-x:$act_x" \
        --bind "ctrl-p:$act_p" \
        --bind "ctrl-o:$act_o" \
        --bind "resize:reload($reload)" \
        --bind 'shift-up:preview-up,shift-down:preview-down' \
        --bind 'alt-up:preview-page-up,alt-down:preview-page-down' \
        --footer "$footer")
    # Backing out of a picker is not a failure. fzf exits 130 on esc/ctrl-c and 1 on no
    # match, and propagating those verbatim painted an error in the prompt every time you
    # looked and changed your mind. Anything else — 2 for an fzf error, 127 for a missing
    # fzf — is a failure and still propagates.
    set -l rc $status
    if test $rc -ne 0
        contains -- $rc 1 130; and return 0
        return $rc
    end

    test -n "$selected"; or return 0
    set -l s (string split \t -- $selected)
    set -l id $s[1]
    set -l spath $s[2]
    set -l scwd $s[3]

    if set -q _flag_trash
        _claude_session_restore "$spath"; or return 1
        echo "ccri: restored $id"
        return 0
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
            echo "ccri: the session's directory no longer exists — $scwd" >&2
            echo "    if it was a git worktree, recreate it, or resume from here with:" >&2
            echo "    claude --resume $id" >&2
            return 1
        end
        cd "$scwd"; or return 1
    end
    # Record the resumed session so a later no-arg `ccr` in this shell follows it.
    set -g _claude_fish_last_session $id
    claude --resume $id
    set -l rc $status
    test "$PWD" = "$back"; or begin
        test -d "$back"; and cd "$back"
    end
    return $rc
end
