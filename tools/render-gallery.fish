#!/usr/bin/env fish
#
# Contact sheet for the preview renderer: every look, one after another, real colours.
# A development aid — it lives outside functions/ and completions/, so fisher never
# installs it.
#
#   fish tools/render-gallery.fish              both galleries
#   fish tools/render-gallery.fish turns        only the turn styles
#   fish tools/render-gallery.fish themes       only the colour themes
#   fish tools/render-gallery.fish all <path>   use a specific .jsonl transcript
#
# Each sample prints the exact `set -U` line that produces it, so picking one is a copy.

# Self-locating, so it works from any checkout and without the plugin installed.
set -l here (path dirname (status filename))
set -p fish_function_path (path resolve $here/../functions)

set -l what $argv[1]
test -z "$what"; and set what all
set -l file $argv[2]

if test -z "$file"
    # Prefer a transcript containing a fenced code block: that is where the renderers differ
    # most, and where the wrapping decisions actually show.
    set -l root "$HOME/.claude/projects"
    set -q CLAUDE_FISH_PROJECTS_ROOT; and set root $CLAUDE_FISH_PROJECTS_ROOT
    set file (grep -rl '```' $root --include='*.jsonl' 2>/dev/null | head -1)
    test -n "$file"; or set file (find $root -name '*.jsonl' -size +100k 2>/dev/null | head -1)
end
if test -z "$file"; or not test -f "$file"
    echo "render-gallery: no transcript found — pass one as the second argument" >&2
    exit 1
end

if not type -q mdcat
    echo "render-gallery: mdcat is not installed, so only the built-in renderer is shown." >&2
    echo "                brew install mdcat" >&2
    echo >&2
end

set -gx FZF_PREVIEW_COLUMNS 72

set -l bold (set_color -o)
set -l dim (set_color -d)
set -l rst (set_color normal)

echo "$dim"(string replace -- "$HOME" '~' "$file")"$rst"

# Print the window of the render that contains a turn, so each sample shows the role marker
# plus some body instead of the metadata header.
function _rg_sample -a label setline file
    set -l bold (set_color -o)
    set -l dim (set_color -d)
    set -l rst (set_color normal)
    set -l lines (_claude_session_preview $file)
    set -l start 1
    for i in (seq (count $lines))
        if string match -qr '┏━|━━|── |> \*\*|▸ ' -- $lines[$i]
            set start $i
            break
        end
    end
    set -l stop (math "min($start + 8, "(count $lines)")")
    echo
    echo "$bold$label$rst  $dim$setline$rst"
    echo "$dim"(string repeat -n 72 ─)"$rst"
    printf '%s\n' $lines[$start..$stop]
end

if contains -- $what all turns
    echo
    echo "$bold══ claude_fish_turns ═══════════════════════════════════════════════════$rst"
    for t in frame heading
        set -gx claude_fish_turns $t
        _rg_sample "turns = $t" "set -U claude_fish_turns $t" $file
    end
    set -e claude_fish_turns
end

if contains -- $what all themes
    echo
    echo "$bold══ claude_fish_theme ═══════════════════════════════════════════════════$rst"
    for th in dark light nord dracula gruvbox-dark gruvbox-light \
        catppuccin-mocha catppuccin-latte solarized-dark solarized-light
        set -gx claude_fish_theme $th
        _rg_sample "theme = $th" "set -U claude_fish_theme $th" $file
    end
    set -e claude_fish_theme
end

if contains -- $what all
    echo
    echo "$bold══ renderer ════════════════════════════════════════════════════════════$rst"
    _rg_sample 'renderer = mdcat (default)' '(nessuna impostazione)' $file
    set -gx claude_fish_renderer ansi
    _rg_sample 'renderer = ansi' 'set -U claude_fish_renderer ansi' $file
    set -e claude_fish_renderer
end

echo
echo "$dim(le impostazioni vanno con set -U o -x: fzf esegue il preview in un processo figlio,$rst"
echo "$dim che i globali non li eredita)$rst"
