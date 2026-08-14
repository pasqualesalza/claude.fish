function _claude_session_preview --description "Render a Claude Code session transcript for the fzf preview pane"
    # --full is for read mode: same styling, but read further back, stop clipping each
    # message, and include thinking blocks, since you are there to read rather than glance.
    argparse f/full -- $argv 2>/dev/null; or return 1
    set -l path $argv[1]
    set -l query $argv[2]
    # `full` reads much further back and stops clipping messages. It is what ctrl-o uses,
    # and `set -U claude_fish_preview full` makes it the pane's normal behaviour too — at a
    # real cost, since the pane re-renders on every cursor move: measured 236ms → 1015ms on a
    # 3.9MB session that renders 6500 lines. Cheap sessions barely notice (+2ms).
    set -l full 0
    set -q _flag_full; and set full 1
    if set -q claude_fish_preview; and test "$claude_fish_preview" = full
        set full 1
    end

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
            set -l framing 0
            set -l mdcols $cols
            if not set -q claude_fish_turns; or test "$claude_fish_turns" = frame
                set framing 1
                set mdcols (math $cols - 2)
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
                # Two SGR parameter strings, user then assistant. Digits and semicolons only:
                # these are interpolated into an escape sequence, so nothing else belongs.
                set -l ucol '1;32'
                set -l acol '1;36'
                if set -q claude_fish_role_colors[2]
                    and string match -qr '^[0-9;]+$' -- "$claude_fish_role_colors[1]"
                    and string match -qr '^[0-9;]+$' -- "$claude_fish_role_colors[2]"
                    set ucol $claude_fish_role_colors[1]
                    set acol $claude_fish_role_colors[2]
                end
                set out ($md "$path" | mdcat $mdopts - 2>/dev/null \
                    | awk -v w=$cols -v ucol=$ucol -v acol=$acol "$(_claude_frame_awk)" \
                    | string collect)
            else
                set out ($md "$path" | mdcat $mdopts - 2>/dev/null | string collect)
            end
            if test -n "$out"
                if test -n "$query"
                    set -l pat (string join '|' (string escape --style=regex (string split -n ' ' -- $query)))
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
    set -l id (string replace -r '\.jsonl$' '' -- (path basename "$path"))
    set -l mtime (stat -f '%m' "$path" 2>/dev/null)
    test -n "$mtime"; or set mtime (stat -c '%Y' "$path" 2>/dev/null)
    set -l size (du -h "$path" 2>/dev/null | cut -f1 | string trim)
    set -l facts
    test -n "$size"; and set -a facts "$size"
    test -n "$mtime"; and set -a facts (string trim -- (_claude_reltime $mtime))
    for l in (_claude_live_sessions)
        set -l lp (string split \t -- $l)
        test "$lp[1]" = "$id"; and set -a facts "open now ($lp[2])"
    end
    set -a facts (string sub -l 8 -- $id)

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
    set -l prog '
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
      # A coloured left rule down every line of a turn, the way cchb blocks off speakers.
      def gutter($c): "\u001b[" + $c + "m│\u001b[0m " + gsub("\n"; "\n\u001b[" + $c + "m│\u001b[0m ");
      def msgtext(m):
        (m.content) as $c
        | ( if   ($c|type) == "string" then $c
            elif ($c|type) == "array"  then
              ([ $c[0:80][] | if type=="object" then (.text // (if $think == 1 then .thinking else null end) // "")
                              elif type=="string" then . else "" end ] | join("\n"))
            else "" end );
      [ .[] | select(type=="object") ] as $recs
      | ( [ $recs[] | select(.type=="custom-title") | .customTitle ] | last ) as $custom
      | ( [ $recs[] | select(.type=="ai-title") | .aiTitle ] | last ) as $ai
      | ( [ $recs[] | select(.type=="agent-name") | .agentName ] | last ) as $agent
      | ( [ $recs[] | select(.type=="last-prompt") | .lastPrompt ] | last ) as $last
      | ( [ $recs[] | select(.type=="user" and ((.isMeta // false) | not)) | msgtext(.message) | select(nz) ] | first ) as $firstuser
      | ( [ $recs[] | .cwd // empty ] | last ) as $cwd
      | ( [ $recs[] | .gitBranch // empty | select(nz) ] | last ) as $branch
      | ( [ $recs[] | select(.type=="assistant") | .message.model // empty | select(nz) ] | last ) as $model
      | ( if ($custom | nz) then "✎ " + $custom
          elif ($ai | nz) then $ai
          elif ($agent | nz) then $agent
          elif ($firstuser | nz) then $firstuser
          else "(untitled)" end ) as $title
      | ( [ (($cwd // "") | sub("^" + $home; "~")), $branch, $model ] | map(select(nz)) | join(" · ") ) as $where
      | ( "\u001b[1m" + $title + "\u001b[0m"
          + (if ($where | nz) then "\n\u001b[2m" + $where + "\u001b[0m" else "" end)
          + "\n\u001b[2m" + $facts + "\u001b[0m"
          + (if ($last | nz) then "\n\u001b[2m↩ last: " + ($last | .[0:500] | gsub("[ \t\n\r]+"; " ") | .[0:240]) + "\u001b[0m" else "" end)
          + "\n\u001b[2m" + ("─" * 60) + "\u001b[0m" ),
        ( $recs[]
          | select(.type=="user" or .type=="assistant")
          | (.type == "user") as $isuser
          | msgtext(.message) as $t
          | select($t | nz)
          | (if $isuser then "32" else "36" end) as $c
          | "\n" + "\u001b[1;" + $c + "m▸ " + (if $isuser then "user" else "assistant" end) + "\u001b[0m"
            + "\n" + (($t | .[0:$cap] | render) + (if ($t | length) > $cap then "\u001b[2m …\u001b[0m" else "" end) | gutter($c)) )'

    set -l jqargs --arg facts (string join ' · ' $facts) --arg home "$HOME" \
        --argjson cap $cap --argjson think $think

    if test -n "$query"
        set -l terms (string escape --style=regex (string split -n ' ' -- $query))
        set -l pat (string join '|' $terms)
        _claude_session_records "$path" $lines | jq -rs $jqargs "$prog" 2>/dev/null | grep -iE --color=always -- "$pat|\$"
    else
        _claude_session_records "$path" $lines | jq -rs $jqargs "$prog" 2>/dev/null
    end
end
