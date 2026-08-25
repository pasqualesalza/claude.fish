# Covers the picker's write side (pin, trash, restore) and the liveness registry
# that guards it. Everything runs against a throwaway copy of the fixtures — no
# real session is ever touched.
set -l here (status dirname)
# Source EVERY helper, by glob rather than by list. A function left off a hand-written list
# is still resolvable from the user's installed plugin, so the test silently exercises the
# INSTALLED copy instead of this checkout — that bit twice: once hiding the real preview
# behind a stale installed one, once making the frame tests fail because the awk helper
# resolved to nothing.
for f in "$here"/../functions/_claude_*.fish
    source $f
end

set -l sand (mktemp -d)
mkdir -p "$sand/.claude" "$sand/.claude/sessions" "$sand/state"
cp -R "$here/fixtures/projects" "$sand/.claude/projects"
set -l id1 11111111-1111-4111-8111-111111111111
set -l id3 33333333-3333-4333-8333-333333333333
mkdir -p "$sand/.claude/session-env/$id1"
echo hook >"$sand/.claude/session-env/$id1/start.sh"

set -gx CLAUDE_FISH_PROJECTS_ROOT "$sand/.claude/projects"
set -gx CLAUDE_FISH_SESSIONS_DIR "$sand/.claude/sessions"
set -gx CLAUDE_FISH_STATE_DIR "$sand/state"
set -e CLAUDE_FISH_TRASH_ROOT

# --- relative age -----------------------------------------------------------
@test "reltime renders minutes" (string trim -- (_claude_reltime (math (date +%s) - 300))) = 5m
@test "reltime renders hours" (string trim -- (_claude_reltime (math (date +%s) - 7200))) = 2h
@test "reltime tolerates junk" (string trim -- (_claude_reltime nope)) = ""

# --- liveness registry ------------------------------------------------------
# A registry file outlives its process, so a dead pid must not count as live.
echo '{"pid":'$fish_pid',"sessionId":"'$id1'","status":"busy"}' >"$sand/.claude/sessions/live.json"
echo '{"pid":999999,"sessionId":"'$id3'","status":"idle"}' >"$sand/.claude/sessions/stale.json"
set -l live (_claude_live_sessions)
@test "only live pids count" (count $live) -eq 1
@test "reports the live session id and status" "$live[1]" = "$id1	busy"

# --- pins -------------------------------------------------------------------
_claude_session_pin $id1
@test "pin is recorded" (count (_claude_pins)) -eq 1
# Records are NUL-separated (one entry spans two rendered lines), so `string split0`
# is how a caller gets one element per session.
# Rows are budgeted to a width so they end on purpose instead of being sliced by the pane
# border. The transcript snippet still has to be in the searched field — it is what lets you
# fuzzy-search words said inside a session — so the visible part is padded out to the full
# width first, which pushes the snippet entirely past the border: searched, never seen.
set -l esc0 (printf '\033')
for rec in (_claude_sessions_table --all --width 40 | string split0)
    set -l meta (string split \n -- (string split \t -- $rec)[1])[2]
    set -g __vis (string sub -l 40 -- (string replace -ra $esc0'\[[0-9;?]*[a-zA-Z]' '' -- $meta))
    break
end
@test "the visible row keeps to its width" (string length -- "$__vis") -le 40
@test "the visible row shows age and place" (string match -qr '^\s+\S+ · \S' -- "$__vis"; and echo yes; or echo no) = yes
@test "the snippet stays past the border" (string match -q '*envoy*' -- "$__vis"; and echo leaked; or echo hidden) = hidden

# The branch is dropped when it only repeats the worktree: `worktree-picker-manage` beside
# `.../picker-manage` says the same thing twice, and that redundancy is what pushed rows over
# the edge. The fixture's cwd is /tmp/proj on branch main, so there nothing is redundant.
set -l wdir (mktemp -d)
mkdir -p "$wdir/projects/enc"
printf '%s\n' \
    '{"type":"ai-title","aiTitle":"wt"}' \
    '{"type":"user","cwd":"/Users/x/repo/.claude/worktrees/feature-a","gitBranch":"worktree-feature-a","message":{"role":"user","content":[{"type":"text","text":"ciao"}]}}' >"$wdir/projects/enc/22222222-2222-4222-8222-222222222222.jsonl"
set -l saved_root $CLAUDE_FISH_PROJECTS_ROOT
set -gx CLAUDE_FISH_PROJECTS_ROOT "$wdir/projects"
set -l wt_meta (string split \n -- (string split \t -- (_claude_sessions_table --all --width 60 | string split0)[1])[1])[2]
set -gx CLAUDE_FISH_PROJECTS_ROOT $saved_root
@test "a redundant branch is dropped from the row" (string match -q '*worktree-feature-a*' -- "$wt_meta"; and echo kept; or echo dropped) = dropped
@test "the worktree itself still shows" (string match -q '*repo/feature-a*' -- "$wt_meta"; and echo yes; or echo no) = yes
rm -rf "$wdir"

set -l tbl (_claude_sessions_table --all | string split0)
@test "pinned row sorts first" (string match -q '*★*' "$tbl[1]"; and echo yes; or echo no) = yes
@test "live session is marked" (string match -q '*●*' "$tbl[1]"; and echo yes; or echo no) = yes
_claude_session_pin $id1
@test "pin toggles off" (count (_claude_pins)) -eq 0

# --- trash refuses a live session -------------------------------------------
_claude_session_delete "$sand/.claude/projects/dummy/$id1.jsonl" 2>/dev/null
@test "refuses to trash an open session" (test -f "$sand/.claude/projects/dummy/$id1.jsonl"; and echo yes; or echo no) = yes

# The refusal must reach the picker's header, which is the only channel fzf renders.
# It also has to be a single line and survive `(busy)`-style parentheses verbatim.
set -l notice (_claude_picker_header)
@test "refusal explains itself in the header" (string match -q '*open in another terminal*' -- "$notice"; and echo yes; or echo no) = yes
@test "header notice is a single line" (count $notice) -eq 1
# Emoji are out on purpose: a glyph like U+1F5D1 declares 1 column but renders as 2,
# which would shift every column that follows it.
@test "no emoji in the notice" (string match -qr '[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]' -- "$notice"; and echo dirty; or echo clean) = clean
# The header carries ONLY a notice, so once consumed it goes empty and the line
# disappears; the permanent hints live in the footer.
@test "notice is consumed, header goes empty" (count (_claude_picker_header)) -eq 0
@test "footer carries the key hints" (string match -q '*ctrl-x trash*' -- (_claude_picker_footer); and echo yes; or echo no) = yes
@test "read mode footer shows the scroll keys" (string match -q '*scroll*' -- (_claude_picker_footer --read); and echo yes; or echo no) = yes
# Footers are injected into fzf bind actions via transform-footer. A ")" in the text
# would terminate the action early and silently break the binding.
@test "no footer text contains a paren" (string match -q '*)*' -- (_claude_picker_footer)(_claude_picker_footer --read)(_claude_picker_footer --trash); and echo dirty; or echo clean) = clean
# Reading the header consumes the notice, so capture it once and assert on that.
_claude_session_notice --set 'gira (busy) su piu
righe'
set -l collapsed (_claude_picker_header)
@test "notice collapses to one line" (count $collapsed) -eq 1
@test "notice keeps parentheses verbatim" (string match -q '*(busy)*' -- "$collapsed"; and echo yes; or echo no) = yes
@test "trash-mode footer differs" (string match -q '*enter restore*' -- (_claude_picker_footer --trash); and echo yes; or echo no) = yes

# --- trash an idle session --------------------------------------------------
_claude_session_notice --consume >/dev/null
_claude_session_delete "$sand/.claude/projects/dummy2/$id3.jsonl"
@test "a successful trash says so, with the undo route" (string match -q '*ccri --trash*' -- (_claude_picker_header); and echo yes; or echo no) = yes
@test "trashed transcript leaves the projects tree" (test -f "$sand/.claude/projects/dummy2/$id3.jsonl"; and echo still; or echo gone) = gone
@test "trashed transcript lands in the trash" (test -f "$sand/.claude/.claude-fish-trash/dummy2/$id3.jsonl"; and echo yes; or echo no) = yes
@test "trashed session drops out of the picker" (count (_claude_sessions_table --all | string split0)) -eq 1
@test "trashed session shows up in --trash" (count (_claude_sessions_table --trash | string split0)) -eq 1

# --- sidecars follow the transcript ----------------------------------------
rm "$sand/.claude/sessions/live.json"
_claude_session_delete "$sand/.claude/projects/dummy/$id1.jsonl"
@test "sidecar state follows into the trash" (test -d "$sand/.claude/.claude-fish-trash/.sidecars/$id1/session-env"; and echo yes; or echo no) = yes
@test "no orphaned sidecar is left behind" (test -d "$sand/.claude/session-env/$id1"; and echo still; or echo gone) = gone

# --- restore ---------------------------------------------------------------
_claude_session_restore "$sand/.claude/.claude-fish-trash/dummy/$id1.jsonl"
@test "restore puts the transcript back" (test -f "$sand/.claude/projects/dummy/$id1.jsonl"; and echo yes; or echo no) = yes
@test "restore puts the sidecar back" (test -d "$sand/.claude/session-env/$id1"; and echo yes; or echo no) = yes

cp "$sand/.claude/projects/dummy/$id1.jsonl" "$sand/.claude/.claude-fish-trash/dummy/$id1.jsonl"
_claude_session_restore "$sand/.claude/.claude-fish-trash/dummy/$id1.jsonl" 2>/dev/null
@test "restore never overwrites a live transcript" (test -f "$sand/.claude/.claude-fish-trash/dummy/$id1.jsonl"; and echo yes; or echo no) = yes

# --- the picker's binds must work in a CHILD shell ---------------------------
# fzf runs previews and binds through `$SHELL -c`, and a child fish does not inherit
# fish_function_path. Without ccri's self-locating prefix the binds resolve nothing —
# or worse, resolve a stale installed copy — so assert the prefix actually works from
# a shell that has no idea where this checkout lives.
set -l fdir (path resolve "$here/../functions")
set -l pre "set -p fish_function_path "(string escape -- $fdir)"; "
@test "table builds in a child shell" (count (fish -c "$pre"'_claude_sessions_table --all' | string split0)) -ge 1
# A roomy record must stay ONE entry spanning two lines. If `string collect` ever gets
# dropped from the table builder, fish splits on the newline and every session shows up
# twice — which looks like an fzf bug, not a quoting bug.
set -l one_entry (_claude_sessions_table --all | string split0)
@test "a record is one entry, not two" (count $one_entry) -eq 1
@test "a record renders on two lines" (count (string split \n -- (string split \t -- $one_entry[1])[1])) -eq 2
@test "field 2 of a record is still the id" (string match -qr '^[0-9a-f-]{36}$' -- (string split \t -- $one_entry[1])[2]; and echo yes; or echo no) = yes
@test "preview renders in a child shell" (fish -c "$pre"'_claude_session_preview '(string escape -- "$sand/.claude/projects/dummy/$id1.jsonl") | count) -ge 3

# The preview's jq program renders inline markdown. A syntax error in it makes jq exit
# non-zero, stderr is discarded, and the pane just goes BLANK — no error anywhere. So
# assert the styling actually reaches the output: [22m (bold-off) is emitted only by the
# `style` helper, so it is a precise canary for that program still compiling.
set -l esc (printf '\033')
set -l styled (_claude_session_preview "$sand/.claude/projects/dummy/$id1.jsonl" | string collect)
@test "preview is not silently blank" (test -n "$styled"; and echo yes; or echo no) = yes
@test "preview emits ANSI" (string match -qr "$esc\[" -- "$styled"; and echo yes; or echo no) = yes

# --- the markdown path -------------------------------------------------------
# The preview prefers mdcat (real markdown: tables, nested lists, wrapping) and falls back
# to the hand-rolled ANSI when it is missing or when the renderer is pinned to `ansi`.
set -l md (_claude_session_markdown "$sand/.claude/projects/dummy/$id1.jsonl")
# The header is built by _claude_session_head, not by the markdown emitter, because fzf can pin
# the first N preview lines with `--preview-window ~N` and N has to be a constant. So the header
# must ALWAYS be four lines and never wrap — which is why each line is truncated to the width.
@test "the markdown carries no header" (string match -q '*`*' -- "$md[1]"; and echo header; or echo turns) = turns

set -l hd (_claude_session_head "$sand/.claude/projects/dummy/$id1.jsonl" 60)
@test "the header is exactly three lines" (count $hd) -eq 3
@test "line 1 is the title" (string match -q '*envoy work*' -- "$hd[1]"; and echo yes; or echo no) = yes
# The sandbox copy was made a moment ago, so its age reads `now` rather than a number.
@test "line 2 carries age and place" (string match -qr '(\d+[mhd]|now) · ' -- "$hd[2]"; and echo yes; or echo no) = yes
set -l esc1 (printf '\033')
set -g __hdover 0
for l in $hd
    # Strip EVERY escape sequence, not just the ones ending in `m`: `set_color normal` also emits
    # a charset selector (ESC ( B) on some terminfo, which survived a narrower pattern and counted
    # as three columns — the assertion then failed on fish 3.7 in a container for a header that was
    # the right width all along.
    set -l p (string replace -ra $esc1'\([A-Z]' '' -- (string replace -ra $esc1'\[[0-9;?]*[a-zA-Z]' '' -- $l))
    test (string length -- "$p") -gt 60; and set __hdover (math $__hdover + 1)
end
@test "no header line exceeds the width" $__hdover -eq 0

# The `↩` alone gave no clue what the line was, so it is labelled now. The shared fixture has
# no last-prompt record, so this needs its own file.
set -l ldir (mktemp -d)
printf '%s\n' \
    '{"type":"ai-title","aiTitle":"con last"}' \
    '{"type":"last-prompt","lastPrompt":"dove mi ero fermato"}' \
    '{"type":"user","cwd":"/tmp/p","message":{"role":"user","content":[{"type":"text","text":"ciao"}]}}' >"$ldir/l.jsonl"
# The header no longer quotes the last prompt: the pane opens scrolled to the bottom, so the
# last exchange is there in full rather than squeezed onto one truncated line.
set -l lhead (string join ' ' -- (_claude_session_head "$ldir/l.jsonl" 80))
@test "the header does not quote the last prompt" (string match -q '*dove mi ero fermato*' -- "$lhead"; and echo quoted; or echo absent) = absent
@test "a session with a last prompt still gets three lines" (count (_claude_session_head "$ldir/l.jsonl" 60)) -eq 3
rm -rf "$ldir"
@test "markdown emitter marks roles as h2" (string match -q '*## user*' -- (string join ' ' -- $md); and echo yes; or echo no) = yes

# The frame is an awk pass over a markdown renderer's output, so it is tested BOTH ways: the awk
# on its own here, which runs anywhere, and end to end below, which needs mdcat. CI has no mdcat —
# only fish, fishtape and the jq that ships with the runner image — so without this the frame logic
# would have had no coverage there at all, and nine assertions would simply have gone red.
set -l fake_md (printf '\u2501\u2501 user\n\nchiedo\n\n\u2501\u2501 assistant\n\nrispondo\n\nancora\n')
set -l framed_awk (printf '%s\n' $fake_md | awk -v w=40 -v ucol=1\;32 -v acol=1\;36 (_claude_frame_awk | string collect))
set -l esc1 (printf '\033')
set -l plain_awk (string replace -ra $esc1'\[[0-9;?]*[a-zA-Z]' '' -- $framed_awk)
@test "the awk pass turns a role heading into a frame" (string match -q '┏━ user *' -- "$plain_awk[1]"; and echo yes; or echo no) = yes
# One column over and the terminal soft-wraps every frame, leaving an orphan ━ on its own row —
# which is exactly what it did.
@test "the frame rule is exactly the width it is given" (string length -- "$plain_awk[1]") -eq 40
@test "the body runs under a spine" (string match -q '┃ chiedo' -- "$plain_awk[2]"; and echo yes; or echo no) = yes
# The blank line mdcat puts before the next element must not become a spine with nothing beside
# it: that was one wasted row per turn, 40 of a 165-row render, including the row the pane is
# anchored on. Blank lines BETWEEN paragraphs of one turn are kept.
set -l orphan_awk 0
for i in (seq 1 (math (count $plain_awk) - 1))
    string match -qr '^┃\s*$' -- $plain_awk[$i]; or continue
    string match -q '┏━*' -- $plain_awk[(math $i + 1)]; and set orphan_awk (math $orphan_awk + 1)
end
@test "no frame closes on an empty spine" $orphan_awk -eq 0
@test "the render does not end on an empty spine" (string match -qr '^┃\s*$' -- "$plain_awk[-1]"; and echo empty; or echo text) = text
# Counted rather than indexed: the position depends on how many paragraphs the input has, and an
# index that happens to be right today is an assertion about the fixture, not about the behaviour.
@test "a paragraph break inside a turn is kept" (string match -r '^┃\s*$' -- $plain_awk | count) -ge 1
# Roles must be distinguishable by colour, not just by the word: mdcat gives every heading the
# same colour, so only this pass can tell them apart.
set -l green $esc1'[1;32m'
set -l cyan $esc1'[1;36m'
@test "the user frame is green" (string match -q "$green┏━ user*" -- "$framed_awk[1]"; and echo yes; or echo no) = yes
@test "the assistant frame is cyan" (string match -q "*$cyan┏━ assistant*" -- (string join \x1e -- $framed_awk); and echo yes; or echo no) = yes

# Everything below here goes through mdcat, so it only runs where mdcat exists. The fallback has
# its own assertions further down.
if type -q mdcat
    # claude_fish_turns has two values now: `frame` (default) and `heading`. Roles are always `##`
    # in the markdown; the choice is only whether the preview draws a box around them.
    set -gx claude_fish_turns frame
    # `frame` is not a markdown construct — mdcat cannot draw boxes — it is an awk pass over the
    # rendered output, so assert on the rendered pane rather than on the markdown.
    set -l framed (_claude_session_preview "$sand/.claude/projects/dummy/$id1.jsonl")
    # One end-to-end check that mdcat's output really does get framed. The frame's own properties
    # — rule width, spine, the dropped trailing blank, the per-role colours — are asserted against
    # the awk pass above, which runs everywhere; repeating them here only duplicated them inside
    # the one block CI cannot execute.
    @test "turns=frame frames mdcat's output" (string match -q '*┏━*' -- (string join ' ' -- $framed); and echo yes; or echo no) = yes

end

# Claude Code injects machinery as ordinary `user` turns — and does NOT flag them isMeta, so
# the field cannot be used. They must not reach the pane: a wall of <task-id> where a question
# should be. A real message that merely follows one must still survive.
set -l ndir (mktemp -d)
printf '%s\n' '{"type":"ai-title","aiTitle":"noise"}' \
    '{"type":"user","cwd":"/tmp/x","message":{"role":"user","content":[{"type":"text","text":"<task-notification>\n<task-id>abc</task-id>\n</task-notification>"}]}}' \
    '{"type":"user","cwd":"/tmp/x","message":{"role":"user","content":[{"type":"text","text":"a real question"}]}}' >"$ndir/n.jsonl"
set -l noisy (string join \x1e -- (_claude_session_preview "$ndir/n.jsonl"))
@test "injected user turns are dropped" (string match -q '*task-notification*' -- "$noisy"; and echo leaked; or echo clean) = clean
@test "a real message next to one survives" (string match -q '*a real question*' -- "$noisy"; and echo yes; or echo no) = yes
rm -rf "$ndir"

# One reply is many records — the assistant emits a fresh one per text block between tool
# calls — so consecutive records of the same role are a single conversational turn. Without
# merging, a real session showed 1047 assistant records for 15 turns, with runs up to 82.
# Asserted on the markdown, so it holds whichever renderer is in play.
set -l mdir (mktemp -d)
begin
    echo '{"type":"ai-title","aiTitle":"runs"}'
    echo '{"type":"user","cwd":"/tmp/x","message":{"role":"user","content":[{"type":"text","text":"chiedo"}]}}'
    for i in 1 2 3
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"passo '$i'"}]}}'
    end
    echo '{"type":"user","cwd":"/tmp/x","message":{"role":"user","content":[{"type":"text","text":"e poi"}]}}'
end >"$mdir/m.jsonl"
set -l runs (string join \x1e -- (_claude_session_markdown "$mdir/m.jsonl"))
@test "consecutive same-role records merge into one turn" (string match -ra '## assistant' -- "$runs" | count) -eq 1
@test "merging keeps every part of the reply" (string match -q '*passo 1*passo 2*passo 3*' -- "$runs"; and echo yes; or echo no) = yes
@test "merging does not swallow the surrounding user turns" (string match -ra '## user' -- "$runs" | count) -eq 2
rm -rf "$mdir"
# Both of these are about what mdcat's output is turned into, so they need mdcat; the awk pass
# above is what covers the framing itself where there is none.
if type -q mdcat
    set claude_fish_turns heading
    @test "turns=heading leaves mdcat's own rendering alone" (string match -q '*┏━*' -- (string join ' ' -- (_claude_session_preview "$sand/.claude/projects/dummy/$id1.jsonl")); and echo framed; or echo plain) = plain
    set claude_fish_turns nonsense
    @test "an unknown turns value still frames" (string match -q '*┏━*' -- (string join ' ' -- (_claude_session_preview "$sand/.claude/projects/dummy/$id1.jsonl")); and echo yes; or echo no) = yes
end
set -e claude_fish_turns

# A bad theme must never blank the pane: mdcat exits non-zero and we fall back. A theme
# carrying shell metacharacters must be rejected before it reaches the command line.
set -gx claude_fish_theme does-not-exist-at-all
@test "an unknown theme degrades instead of blanking" (count (_claude_session_preview "$sand/.claude/projects/dummy/$id1.jsonl")) -ge 3
set claude_fish_theme 'nord; echo pwned'
@test "a theme with metacharacters is rejected" (count (_claude_session_preview "$sand/.claude/projects/dummy/$id1.jsonl")) -ge 3
set -e claude_fish_theme

set -gx claude_fish_renderer ansi
set -l forced (_claude_session_preview "$sand/.claude/projects/dummy/$id1.jsonl")
@test "renderer can be pinned to the ANSI fallback" (string match -q '*│*' -- (string join ' ' -- $forced); and echo yes; or echo no) = yes
# Everything this renderer emits must be an ANSI *index*, so it inherits the terminal's theme.
# A 38;5;N entry above 15, or a 38;2;R;G;B triplet, is a fixed colour that ignores it — the
# code-block body used to be 38;5;108 and silently broke that promise.
@test "the fallback uses no fixed palette colours" (string match -q '*38;5;*' -- (string join ' ' -- $forced); or string match -q '*38;2;*' -- (string join ' ' -- $forced); and echo fixed; or echo indices) = indices
set -e claude_fish_renderer

# Only meaningful where mdcat exists — CI will not have it, and the fallback above is what
# guarantees the plugin still works there.
if type -q mdcat
    set -l rendered (_claude_session_preview "$sand/.claude/projects/dummy/$id1.jsonl")
    @test "mdcat path renders role rules" (string match -q '*━━*' -- (string join ' ' -- $rendered); and echo yes; or echo no) = yes
end

# Title records are grepped from a tail window for speed, with a whole-file fallback. A
# session whose title was set once at the very start and never touched again must still
# show it — otherwise the optimisation silently downgrades titles on long sessions.
set -l bigdir (mktemp -d)
echo '{"type":"custom-title","customTitle":"OLD TITLE"}' >"$bigdir/big.jsonl"
for i in (seq 1 12000)
    echo '{"type":"assistant","message":{"content":[{"type":"text","text":"filler filler filler filler filler filler filler filler filler filler filler filler"}]}}' >>"$bigdir/big.jsonl"
end
# Match anywhere in the output, not on line 1: the two renderers put the title on
# different lines (mdcat opens with blank lines), and the assertion is about the title
# being FOUND, not about where it lands.
@test "title outside the tail window is still found" (string match -q '*OLD TITLE*' -- (string join ' ' -- (_claude_session_preview "$bigdir/big.jsonl")); and echo yes; or echo no) = yes
rm -rf "$bigdir"
# --- a session being written to right now -----------------------------------
# Claude appends while we read, so a live transcript can end in half a record. jq -s aborts on
# the first parse error, which used to take the whole body with it: the pane rendered its header
# and nothing else, and the session dropped out of the list — silently, and precisely for the
# sessions you look at most. Tolerant parsing costs 23ms → 846ms, so the repair is a retry that
# only runs after a failure.
set -l ldir2 (mktemp -d)
mkdir -p "$ldir2/projects/enc"
set -l halffile "$ldir2/projects/enc/11111111-1111-4111-8111-111111111111.jsonl"
for i in (seq 1 12)
    echo '{"type":"assistant","cwd":"/tmp/proj","message":{"content":[{"type":"text","text":"messaggio '$i'"}]}}' >>"$halffile"
end
echo '{"type":"user","cwd":"/tmp/proj","message":{"content":"la mia domanda"}}' >>"$halffile"
# half a record, exactly as a reader catches it mid-append
printf '{"type":"assistant","cwd":"/tmp/proj","message":{"content":[{"type":"te' >>"$halffile"
set -l saved_root2 $CLAUDE_FISH_PROJECTS_ROOT
set -gx CLAUDE_FISH_PROJECTS_ROOT "$ldir2/projects"
@test "a half-written record does not empty the pane" (test (count (_claude_session_preview "$halffile")) -gt 3; and echo yes; or echo no) = yes
@test "the turns before it still render" (string match -q '*messaggio 12*' -- (string join ' ' -- (_claude_session_preview "$halffile")); and echo yes; or echo no) = yes
@test "and the session stays in the list" (_claude_sessions --all | count) -eq 1
@test "with its title" (_claude_sessions --all | cut -f2) = 'la mia domanda'
set -gx CLAUDE_FISH_PROJECTS_ROOT $saved_root2
rm -rf "$ldir2"

# --- rows re-fit after a window resize --------------------------------------
# fzf re-runs the preview by itself when the terminal is resized — measured on a 140 → 90 resize,
# the turn frames follow, 70 columns wide to 43 — but it does NOT rebuild the list, so every row
# kept the budget measured at startup. The reload bound to `resize` asks for `--width auto`, which
# measures the pane at that moment. The first build cannot: fzf reports 0 columns while it is still
# sizing the UI, which is exactly when that build runs.
@test "the width helper follows the terminal" (_claude_list_width 140) -gt (_claude_list_width 70)
@test "and refuses to go absurdly narrow" (_claude_list_width 30) -ge 24
@test "junk falls back to a usable width" (_claude_list_width nope) -eq 56
@test "zero columns — fzf while it sizes the UI — does too" (_claude_list_width 0) -eq 56
set -gx FZF_COLUMNS 140
# The METADATA line, not the title: the title is left as it is, while the second line is the one
# padded out to the budget — which is what pushes the searchable snippet past the border.
set -l wide_row (string split \n -- (string split \t -- (_claude_sessions_table --all --width auto | string split0)[1])[1])[2]
set -gx FZF_COLUMNS 70
set -l narrow_row (string split \n -- (string split \t -- (_claude_sessions_table --all --width auto | string split0)[1])[1])[2]
set -e FZF_COLUMNS
@test "--width auto measures the pane" (string length -- "$wide_row") -gt (string length -- "$narrow_row")

# --- the repository root, from inside a worktree -----------------------------
# `--repo` is the scope between "this exact directory" and "every project on the machine", and it
# hangs on finding the MAIN checkout from wherever you are. `git rev-parse --show-toplevel` is the
# obvious call and the wrong one: inside a worktree it returns the worktree, which would scope the
# picker to the directory you are already in. A real repository with a real worktree is the only
# way to cover that, so this builds one.
set -l gdir (mktemp -d)
set -l gitq git -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false
$gitq init -q "$gdir/repo" 2>/dev/null
$gitq -C "$gdir/repo" commit -q --allow-empty -m base
$gitq -C "$gdir/repo" worktree add -q "$gdir/repo/.claude/worktrees/wt" -b wt 2>/dev/null
set -l here_before $PWD
cd "$gdir/repo"
@test "the repo root is the checkout itself" (_claude_repo_root) = (path resolve "$gdir/repo")
cd "$gdir/repo/.claude/worktrees/wt"
# The point of the whole exercise: from the worktree, the answer is still the main checkout.
@test "and from a worktree it is still the main checkout" (_claude_repo_root) = (path resolve "$gdir/repo")
@test "show-toplevel would have said otherwise" (path resolve (git rev-parse --show-toplevel)) != (path resolve "$gdir/repo")
# Widening: from the worktree there IS somewhere else to look, from the root there is not, and
# outside a repository there is nothing at all. A session is filed under the directory it was
# started in, so that first case is the one where `ccr` used to answer "no sessions found" in the
# very folder you were working in.
@test "from a worktree there is somewhere to widen to" (_claude_widen_root) = (path resolve "$gdir/repo")
cd "$gdir/repo"
@test "from the root there is not" (_claude_widen_root >/dev/null 2>&1; echo $status) -ne 0
cd /
@test "outside a repository it fails" (_claude_repo_root >/dev/null 2>&1; echo $status) -ne 0
@test "and so does widening" (_claude_widen_root >/dev/null 2>&1; echo $status) -ne 0
cd $here_before
$gitq -C "$gdir/repo" worktree remove --force "$gdir/repo/.claude/worktrees/wt" 2>/dev/null
rm -rf "$gdir"

# --- worktrees --------------------------------------------------------------
# A worktree is where much of the work happens, and the picker could not see across them: the
# default scope is the exact directory and `--all` is every project on the machine. `--under`
# fills the gap, and it matches on the cwd rather than on the encoded directory name — encoding
# turns every non-alphanumeric into `-`, so a prefix match there cannot tell `claude.fish` from
# `claude-fish2`.
set -l wroot (mktemp -d)
mkdir -p "$wroot/projects/enc" "$wroot/repo/.claude/worktrees/alpha/src" "$wroot/repo/sub"
set -l saved_root3 $CLAUDE_FISH_PROJECTS_ROOT
set -gx CLAUDE_FISH_PROJECTS_ROOT "$wroot/projects"
function __ccf_sess -a id dir text
    echo '{"type":"user","cwd":"'$dir'","gitBranch":"main","message":{"content":"'$text'"}}' >"$CLAUDE_FISH_PROJECTS_ROOT/enc/$id.jsonl"
end
__ccf_sess 41111111-1111-4111-8111-111111111111 "$wroot/repo" 'nel repo'
__ccf_sess 42222222-2222-4222-8222-222222222222 "$wroot/repo/.claude/worktrees/alpha" 'nel worktree'
__ccf_sess 43333333-3333-4333-8333-333333333333 "$wroot/repo/.claude/worktrees/beta" 'worktree rimosso'
__ccf_sess 44444444-4444-4444-8444-444444444444 "$wroot/altrove" fuori
__ccf_sess 46666666-6666-4666-8666-666666666666 "$wroot/repo/.claude/worktrees/alpha/src" 'nel sottodir'
@test "--under sees the repo and its worktrees" (_claude_sessions --under "$wroot/repo" | count) -eq 4
@test "--under leaves everything else out" (string match -q '*fuori*' -- (_claude_sessions --under "$wroot/repo"); and echo leaked; or echo clean) = clean
# One row per worktree, and only worktrees — the plain repo directory is not one.
set -l wt (_claude_worktrees_table --width 70 | string split0)
@test "the worktree view has a row per worktree" (count $wt) -eq 2
@test "sessions below a worktree root stay in that worktree" (string match -q '*nel sottodir*' -- (string join ' ' -- $wt); and echo yes; or echo no) = yes
@test "and does not list ordinary directories" (string match -q '*nel repo*' -- "$wt"; and echo leaked; or echo clean) = clean
# A removed worktree keeps its transcripts, and those are the ones you could otherwise never find
# again — so it is listed, and marked.
@test "a removed worktree is marked gone" (string match -q '*gone*' -- (string join ' ' -- $wt); and echo yes; or echo no) = yes
# The titles ride along in a hidden field so the preview costs nothing per keystroke.
set -l wt_titles
for rec in $wt
    set -a wt_titles (string split \t -- $rec)[3]
end
@test "the row carries the session titles" (string match -q '*worktree rimosso*' -- (string join ' ' -- $wt_titles); and echo yes; or echo no) = yes

# The header marks a worktree, which `place` alone cannot say: it renders `repo/name` for a
# worktree and for an ordinary subdirectory alike.
set -l whead (_claude_session_head "$CLAUDE_FISH_PROJECTS_ROOT/enc/42222222-2222-4222-8222-222222222222.jsonl" 100)
set -l wplain (string replace -ra (printf '\033')'\[[0-9;?]*[a-zA-Z]' '' -- $whead)
@test "the header marks a worktree session" (string match -q '*⋔*' -- "$wplain[2]"; and echo yes; or echo no) = yes
@test "an ordinary directory gets no mark" (string match -q '*⋔*' -- (string replace -ra (printf '\033')'\[[0-9;?]*[a-zA-Z]' '' -- (_claude_session_head "$CLAUDE_FISH_PROJECTS_ROOT/enc/41111111-1111-4111-8111-111111111111.jsonl" 100))[2]; and echo marked; or echo clean) = clean
# And it says when the directory is gone, where the decision is made — not at the moment you
# press enter and `cd` fails with a bare error.
set -l ghead (string replace -ra (printf '\033')'\[[0-9;?]*[a-zA-Z]' '' -- (_claude_session_head "$CLAUDE_FISH_PROJECTS_ROOT/enc/43333333-3333-4333-8333-333333333333.jsonl" 100))
@test "a missing directory is called out" (string match -q '*directory gone*' -- "$ghead[2]"; and echo yes; or echo no) = yes

# The cwd reported is the LAST one in the transcript, not the first. A session that moves — into a
# worktree, or back out of it — would otherwise be listed against where it started, and `ccr` cd's
# into that field: on a real session it named a worktree deleted since, while the session had
# moved back to the main checkout and was perfectly resumable.
set -l mover "$CLAUDE_FISH_PROJECTS_ROOT/enc/45555555-5555-4555-8555-555555555555.jsonl"
echo '{"type":"user","cwd":"'$wroot'/repo/.claude/worktrees/alpha","message":{"content":"partito nel worktree"}}' >"$mover"
# Past record 200 on purpose: the old rule read the head window only, so a move inside it was
# still caught and a fixture of two records proved nothing. This is where it actually broke.
for i in (seq 1 210)
    echo '{"type":"assistant","cwd":"'$wroot'/repo/.claude/worktrees/alpha","message":{"content":[{"type":"text","text":"lavoro '$i'"}]}}' >>"$mover"
end
echo '{"type":"user","cwd":"'$wroot'/repo","message":{"content":"tornato nel repo"}}' >>"$mover"
@test "the cwd is where the session ended up" (_claude_sessions --all | string match -er 'partito nel worktree' | string split \t)[3] = "$wroot/repo"
# Catch the same transcript while Claude is halfway through appending its next record. The retry
# must discard only that line and still retain the tail carrying the latest cwd.
printf '%s' '{"type":"assistant","cwd":"'$wroot'/repo","message":{"content":"incompleta' >>"$mover"
@test "a half-written long session keeps its latest cwd" (_claude_sessions --all | string match -er 'partito nel worktree' | string split \t)[3] = "$wroot/repo"
functions -e __ccf_sess
set -gx CLAUDE_FISH_PROJECTS_ROOT $saved_root3
rm -rf "$wroot"

# --- backing out of the picker is not a failure ------------------------------
# fzf exits 130 on esc/ctrl-c and 1 on no match. Propagating those verbatim painted an error in
# the prompt every time you opened the picker and changed your mind. Anything else still is a
# failure: 2 is an fzf error, 127 a missing fzf. The picker is stubbed by defining `fzf`, which is
# what ccri calls when fzf.fish's wrapper is absent.
source "$here"/../functions/ccri.fish
for __code in 130 1 2 127
    function fzf --inherit-variable __code
        return $__code
    end
    ccri --all >/dev/null 2>&1
    set -g __ccri_rc_$__code $status
end
functions -e fzf
@test "esc leaves no error behind" $__ccri_rc_130 -eq 0
@test "nor does an empty match" $__ccri_rc_1 -eq 0
@test "an fzf error still propagates" $__ccri_rc_2 -eq 2
@test "and so does a missing fzf" $__ccri_rc_127 -eq 127

@test "delete resolves in a child shell" (fish -c "$pre"'functions -q _claude_session_delete'; and echo yes; or echo no) = yes

# --- fenced code blocks survive clipping ------------------------------------
# A message is clipped at a character budget and the cut lands wherever it lands — including
# inside a fenced block, which leaves the fence open. Markdown has no turn boundaries, so
# mdcat then reads every LATER turn as code too and stops rendering markdown at all: the rest
# of the pane arrives as literal ** and ## headings. It only bites when a clip happens to land
# inside a block, which is why some sessions looked fine and others looked broken.
set -l fdir (mktemp -d)
# Well over the 1200-character clip on purpose, so the cut lands INSIDE the fence.
set -l long (string repeat -n 900 'x ')
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"before\n```fish\n'$long'\n```\ndopo"}]}}' >"$fdir/fence.jsonl"
echo '{"type":"user","message":{"content":"**grassetto** e un titolo"}}' >>"$fdir/fence.jsonl"
# Exactly two, not merely an even count: an empty render would also be even, and that is how
# this assertion passed while proving nothing.
@test "a clipped fence is closed again" (_claude_session_markdown "$fdir/fence.jsonl" | string match -ar '^```' | count) -eq 2
# The proof that matters is at the other end of the renderer: a heading in the turn AFTER the
# clipped one must not reach the pane as literal markdown.
@test "a later turn is not swallowed as code" (string match -q '*## user*' -- (string join \n -- (_claude_session_preview "$fdir/fence.jsonl")); and echo raw; or echo rendered) = rendered
rm -rf "$fdir"

# --- what the pane cuts, and saying so -------------------------------------
# The pane is anchored on the end of the conversation, so the LAST turn keeps its tail while
# earlier ones keep their head. Head-clipping the last turn hid the newest words — the ones the
# pane is opened to read — and it was over budget on all six real sessions measured.
set -l cdir (mktemp -d)
set -l head_marker (string repeat -n 700 'inizio ')
set -l tail_marker (string repeat -n 700 'fine ')
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"APERTURA '$head_marker'CHIUSURA"}]}}' >"$cdir/clip.jsonl"
echo '{"type":"user","message":{"content":"ULTIMO-INIZIO '$tail_marker'ULTIMO-FINE"}}' >>"$cdir/clip.jsonl"
set -l cmd (string join \n -- (_claude_session_markdown "$cdir/clip.jsonl"))
@test "an earlier turn keeps its head" (string match -q '*APERTURA*' -- "$cmd"; and echo yes; or echo no) = yes
@test "an earlier turn drops its tail" (string match -q '*CHIUSURA*' -- "$cmd"; and echo kept; or echo dropped) = dropped
@test "the last turn keeps its tail" (string match -q '*ULTIMO-FINE*' -- "$cmd"; and echo yes; or echo no) = yes
@test "the last turn drops its head" (string match -q '*ULTIMO-INIZIO*' -- "$cmd"; and echo kept; or echo dropped) = dropped
# The marker has to say what it means: a bare … only prompted "what are those?". Its position
# carries the direction — top of a turn means the start went, bottom means the end did — so the
# text only has to carry the amount. Here the cut lands inside a single paragraph, so no whole
# line is missing and there is no number to give.
@test "a cut inside one paragraph says just that" (string match -q '*… more*' -- "$cmd"; and echo yes; or echo no) = yes
# And the cut falls between blocks, never inside one: a message that stops mid-sentence reads
# as damage rather than as a preview. Five paragraphs against a 1200-character budget: whole
# ones survive, the rest go, and no paragraph is left half-rendered.
set -l bdir (mktemp -d)
set -l para (string repeat -n 70 'parola ')
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"P1 '$para'\n\nP2 '$para'\n\nP3 '$para'\n\nP4 '$para'"}]}}' >"$bdir/b.jsonl"
echo '{"type":"user","message":{"content":"corto"}}' >>"$bdir/b.jsonl"
set -l bmd (_claude_session_markdown "$bdir/b.jsonl")
# Every rendered paragraph must still end where it ended in the source.
set -l halved 0
for l in $bmd
    string match -qr '^P[0-9] parola' -- $l; or continue
    string match -qr 'parola $' -- $l; or set halved (math $halved + 1)
end
@test "no paragraph is cut in half" $halved -eq 0
@test "whole paragraphs are what survives" (string match -q '*P1 *' -- (string join \n -- $bmd); and echo yes; or echo no) = yes
@test "and the ones past the budget are gone" (string match -q '*P4 *' -- (string join \n -- $bmd); and echo kept; or echo dropped) = dropped
# Whole lines went here, so the marker can say how many.
@test "a clip between blocks counts the missing lines" (string match -qr '… [0-9]+ more lines' -- (string join \n -- $bmd); and echo yes; or echo no) = yes
# A single block over budget steps down to whole LINES rather than splitting one.
# 400 lines, so the block is well past the 1200-character budget and the cut must happen.
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"```fish\n'(string join '\n' (seq 1 400 | string replace -r '^' 'riga con del codice '))'\n```"}]}}' >"$bdir/c.jsonl"
set -l cmd2 (_claude_session_markdown "$bdir/c.jsonl")
# Check EVERY body line, not the ones that look like code: filtering by content would skip the
# very line a mid-line cut produces, which is how this assertion first passed either way.
set -l broken 0
for l in $cmd2
    string match -qr '^(|## assistant|```.*|\*… .*\*)$' -- $l; and continue
    string match -qr '^riga con del codice [0-9]+$' -- $l; or set broken (math $broken + 1)
end
@test "an oversized block is cut on line boundaries" $broken -eq 0
rm -rf "$bdir"
# Same rule in the no-dependency renderer, so the two never disagree about what you are seeing.
set -gx claude_fish_renderer ansi
# Past the three header lines: with no title record the header echoes the message text, which
# would answer the assertion for the body.
set -l cpv (string join \n -- (_claude_session_preview "$cdir/clip.jsonl")[4..-1])
set -e claude_fish_renderer
@test "the fallback also keeps the last turn's tail" (string match -q '*ULTIMO-FINE*' -- "$cpv"; and echo yes; or echo no) = yes
@test "the fallback also drops the last turn's head" (string match -q '*ULTIMO-INIZIO*' -- "$cpv"; and echo kept; or echo dropped) = dropped
# Only turns inside the record window are rendered, and the pane says so at the top — where you
# arrive when you scroll up, which is exactly when the question comes up.
@test "a short session claims nothing is missing" (string match -q '*outside the preview window*' -- "$cmd"; and echo claims; or echo quiet) = quiet
for i in (seq 1 420)
    echo '{"type":"assistant","message":{"content":[{"type":"text","text":"turno '$i'"}]}}' >>"$cdir/clip.jsonl"
end
@test "a session past the window says so" (string match -q '*outside the preview window*' -- (string join \n -- (_claude_session_markdown "$cdir/clip.jsonl")); and echo yes; or echo no) = yes
@test "read mode reaches further back" (string match -q '*outside the preview window*' -- (string join \n -- (_claude_session_markdown --full "$cdir/clip.jsonl")); and echo still; or echo whole) = whole
rm -rf "$cdir"

rm -rf "$sand"
