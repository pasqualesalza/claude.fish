function _claude_session_preview --description "Render a Claude Code session transcript for the fzf preview pane"
    # --full is for read mode: same styling, but read further back, stop clipping each
    # message, and include thinking blocks, since you are there to read rather than glance.
    argparse f/full -- $argv 2>/dev/null; or return 1
    set -l path $argv[1]
    set -l query $argv[2]
    # `full` reads much further back and stops clipping messages: it is what ctrl-o uses. There
    # is deliberately no setting to make the browse pane behave this way — it re-renders on every
    # cursor move, and that measured 236ms → 1015ms on a 3.9MB session.
    set -l full 0
    set -q _flag_full; and set full 1

    set -l lines 400
    set -l cap 1200
    set -l think 0
    if test $full -eq 1
        set lines 4000
        set cap 100000
        set think 1
    end

    if test -z "$path"; or not test -f "$path"
        echo "(no session selected)"
        return
    end
    type -q jq; or begin
        echo "(jq not found)"
        return
    end

    # Preferred path: hand the transcript to a real markdown renderer. mdcat is the one
    # that fits — it forces ANSI with a single plain flag (`--ansi`), wraps to a width we
    # give it, and adds no padding. glow needs CLICOLOR_FORCE *and* an explicit --style,
    # and an env var travelling through fzf's nested shells is exactly the kind of thing
    # that silently stops working; it also pads every line, 144KB of output where mdcat
    # emits 18KB. Everything below this block is the no-dependency fallback.
    #
    #   --local              never fetch remote resources — the pane must not hit the
    #                        network just because a transcript mentions an image URL
    #   --image-protocol none  don't try to draw images into the pane
    # Exactly three lines, pinned by fzf with `--preview-window ~3` so they stay put while the
    # transcript scrolls under them. Both renderers share it, which is also what stopped the
    # header being built twice in two different jq programs.
    set -l headw 80
    if set -q FZF_PREVIEW_COLUMNS; and test -n "$FZF_PREVIEW_COLUMNS"
        set headw $FZF_PREVIEW_COLUMNS
    end
    _claude_session_head "$path" $headw

    if not set -q claude_fish_renderer; or test "$claude_fish_renderer" != ansi
        if type -q mdcat
            set -l cols 80
            if set -q FZF_PREVIEW_COLUMNS; and test -n "$FZF_PREVIEW_COLUMNS"
                set cols $FZF_PREVIEW_COLUMNS
            end
            set -l md _claude_session_markdown
            test $full -eq 1; and set -a md --full

            # `frame` draws what mdcat cannot: a box around each turn. mdcat's constructs are
            # headings, blockquotes, tables and callouts — none of them a frame — so the frame
            # is added afterwards, in one awk pass over the rendered lines (a few ms). The
            # body then carries a two-column `┃ ` prefix, so mdcat is told to wrap two columns
            # narrower to compensate.
            # Framing is the DEFAULT: it is the only mode where user and assistant are
            # visually distinct, because mdcat gives every heading the same colour and only
            # the awk pass knows which role it is looking at.
            # Framing unless explicitly turned off with `heading`: anything unrecognised falls
            # back to the default, the way the other settings behave.
            set -l framing 1
            set -l mdcols (math $cols - 2)
            if set -q claude_fish_turns; and test "$claude_fish_turns" = heading
                set framing 0
                set mdcols $cols
            end

            # One of mdcat's ten built-in themes (dark, nord, dracula, gruvbox-*,
            # catppuccin-*, solarized-*). Name-shaped values only: an unknown theme makes
            # mdcat exit non-zero, and we would then silently drop to the ANSI fallback.
            set -l mdopts --ansi --local --image-protocol none --columns $mdcols
            if set -q claude_fish_theme; and string match -qr '^[a-z][a-z0-9-]*$' -- "$claude_fish_theme"
                set -a mdopts --theme "$claude_fish_theme"
            end

            set -l out
            if test $framing -eq 1
                # Green for user, cyan for assistant — basic ANSI, so they resolve against the
                # terminal's own palette like everything else the picker draws.
                set -l ucol '1;32'
                set -l acol '1;36'
                set out ($md "$path" | mdcat $mdopts - 2>/dev/null \
                    | awk -v w=$cols -v ucol=$ucol -v acol=$acol "$(_claude_frame_awk)" \
                    | string collect)
            else
                set out ($md "$path" | mdcat $mdopts - 2>/dev/null | string collect)
            end
            if test -n "$out"
                # The whole rendering goes out, top to bottom: landing the pane on the end is
                # the `follow` flag's job in ccri, which leaves the history above to scroll into.
                if test -n "$query"
                    set -l terms (string escape --style=regex (string split -n ' ' -- $query))
                    set -l pat (string join '|' $terms)
                    printf '%s\n' $out | grep -iE --color=always -- "$pat|\$"
                else
                    printf '%s\n' $out
                end
                return 0
            end
        end
    end

    # Cheap metadata that is NOT in the transcript body: size, age, liveness. One
    # stat and a handful of small registry files — the transcript itself is never
    # read twice for this.
    # Recap header (title, where it lives, where you left off) then the most recent
    # messages, so you decide whether to resume at a glance.
    #
    # ANSI is written as jq's \u001b escapes rather than raw ESC bytes: the program then
    # contains no control characters, which keeps it greppable and editable.
    #
    # Markdown is rendered by hand. It cannot be handed to glow: fzf pipes preview output,
    # glow has no force-color flag, and in a pipe it degrades to literal '#' and '**' plus
    # a wasted margin. `render` splits a turn on the ``` fences and alternates: prose goes
    # through the inline rules in `style`, fenced bodies through `codeblock`. Tables and
    # nested lists are still out of reach — those need a real parser.
    #
    # tool_use / tool_result blocks carry neither .text nor .thinking, so they drop out
    # here: that is the single biggest noise reduction available, and the same choice cchb
    # and ccresume make. Thinking blocks are held back too, except in read mode.
    set -l prog (_claude_clip_jq | string collect)'
      def nz: . != null and . != "";
      def style:
          # [*][*] rather than \*\*: a backslash must survive BOTH fish single quotes and
          # jq string parsing, and `\\*` reaches jq as `\*` — not a valid JSON escape, so
          # the program fails to compile and the whole preview silently goes blank.
          gsub("[*][*](?<b>[^*\n]+)[*][*]"; "\u001b[1m" + .b + "\u001b[22m")
        | gsub("`(?<c>[^`\n]+)`"; "\u001b[36m" + .c + "\u001b[39m")
        | gsub("(?<h>^|\n)#{1,6} +(?<t>[^\n]+)"; .h + "\u001b[1m" + .t + "\u001b[22m")
        | gsub("(?<p>^|\n)[-*] +"; .p + "  • ")
        | gsub("(?<p>^|\n)(?<n>[0-9]{1,3})[.)] +"; .p + "  " + .n + ". ")
        | gsub("(?<p>^|\n)> ?(?<q>[^\n]*)"; .p + "  [2m▎ " + .q + "[0m");
      # One fenced block: an optional info string on the first line becomes a dim label,
      # and the body gets a flat colour. No per-token highlighting (cchb does not either) —
      # that would mean a subprocess per block, which a per-keystroke preview cannot afford.
      def codeblock:
          split("\n") as $ls
        | ($ls[0] | test("^[A-Za-z0-9_+#.-]*$")) as $haslang
        | (if $haslang then $ls[0] else "" end) as $lang
        | (if $haslang then $ls[1:] else $ls end) as $code
        | "\u001b[2m─── " + (if $lang == "" then "code" else $lang end) + "\u001b[0m\n"
          # Dim cyan by ANSI index, not the 256-palette entry 108 this used to be: an index
          # is a reference the terminal resolves against its own theme, so it follows the
          # terminal. Entry 108 was a fixed colour that ignored it, and inheriting the
          # terminal is the whole point of this renderer.
          + ([ $code[] | "\u001b[2;36m" + . + "\u001b[0m" ] | join("\n"));
      # Splitting on the fences is what makes code blocks possible at all: the inline rules
      # are stateless, so they cannot know where a block starts — and worse, they used to
      # rewrite markdown INSIDE code, eating a literal ** in a snippet. Chunk 0 is prose,
      # then they alternate. An unterminated final chunk (a truncated message) stays prose
      # rather than turning the rest of the turn into one big code block.
      def render:
          split("```") as $parts
        | ($parts | length) as $n
        | [ range(0; $n) as $i
            | if ($i % 2) == 1 and (($n % 2) == 1 or $i != ($n - 1))
              then ($parts[$i] | codeblock)
              else ($parts[$i] | style) end ]
        | join("");
      # Same clipping rule as the mdcat path: the pane is anchored on the END of the
      # conversation, so the LAST turn keeps its tail and the earlier ones their head. The last
      # turn was over budget on all six sessions measured, so head-clipping it hid exactly the
      # words the pane is opened to read. The dim … says which end went missing.
      def clip($tail):
          if (length <= $cap) then render
          else . as $t
            | ($t | split("\n") | length) as $was
            | clipped($tail; $cap) as $k
            | ($was - ($k | split("\n") | length)) as $gone
            | (if $gone > 1 then "\u001b[2m… " + ($gone|tostring) + " more lines\u001b[0m"
               else "\u001b[2m… more\u001b[0m" end) as $mark
            | if $tail then $mark + "\n" + ($k | render) else ($k | render) + "\n" + $mark end
          end;
      # A coloured left rule down every line of a turn, the way cchb blocks off speakers.
      def gutter($c): "\u001b[" + $c + "m│\u001b[0m " + gsub("\n"; "\n\u001b[" + $c + "m│\u001b[0m ");
      def msgtext(m):
        (m.content) as $c
        | ( if   ($c|type) == "string" then $c
            elif ($c|type) == "array"  then
              ([ $c[0:80][] | if type=="object" then (.text // (if $think == 1 then .thinking else null end) // "")
                              elif type=="string" then . else "" end ] | join("\n"))
            else "" end );
      # Claude Code injects machinery — task notifications, system reminders, command output — as
      # ordinary `user` turns, and does NOT flag them isMeta. The mdcat path has always dropped
      # them; this one did not, so pinning the fallback (or simply not having mdcat, as CI does
      # not) put walls of <task-notification> in the pane. Same regex, so the two agree.
      def injected: test($injected_re);
      [ .[] | select(type=="object") ] as $recs
      | [ $recs[]
          | select(.type=="user" or .type=="assistant")
          | { isuser: (.type == "user"), t: msgtext(.message), ts: (.timestamp // "") }
          | select(.t | nz)
          | select(.t | injected | not) ] as $turns
      | ($turns | length) as $n
      | ( if $more == 1
          then "\u001b[2m… earlier turns are outside the preview window — ctrl-o reads further back\u001b[0m"
          else empty end ),
        ( range(0; $n)
          | . as $i
          | (if $turns[$i].isuser then "32" else "36" end) as $c
          # Same stamp as the mdcat path, from the same shared defs — the clock inside a day, the
          # date as well when the day changes.
          | ($turns[$i] | when(if $i == 0 then null else $turns[$i-1].ts end)) as $w
          | "\n" + "\u001b[1;" + $c + "m▸ " + (if $turns[$i].isuser then "user" else "assistant" end)
            + "\u001b[0m" + (if $w == "" then "" else "  \u001b[2m" + $w + "\u001b[0m" end)
            + "\n" + ($turns[$i].t | clip($i == $n - 1) | gutter($c)) )'

    # Whether anything fell outside the record window, asked from the END of the file so it
    # costs nothing: request one more record than we render and see if it comes back.
    set -l more 0
    test (tail -n (math $lines + 1) "$path" | wc -l | string trim) -gt $lines; and set more 1

    set -l jqargs --arg injected_re (_claude_injected_re) --argjson cap $cap --argjson think $think --argjson more $more

    if test -n "$query"
        set -l terms (string escape --style=regex (string split -n ' ' -- $query))
        set -l pat (string join '|' $terms)
        _claude_records_jq "$path" $lines $jqargs "$prog" \
            | grep -iE --color=always -- "$pat|\$"
    else
        _claude_records_jq "$path" $lines $jqargs "$prog"
    end
end
