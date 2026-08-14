set -l here (status dirname)
source "$here/../functions/ccr.fish"
# Every helper too, by glob: sourcing only ccr.fish left the rest to be autoloaded from whatever
# claude.fish the user has INSTALLED — so a message built with `_claude_place` silently failed here
# while the code under test was fine. The stubs below deliberately replace some of these; they come
# after, so they win.
for f in "$here"/../functions/_claude_*.fish
    source $f
end

# Stub `claude` so `--resume <id>` records the id instead of launching anything.
functions -e claude
set -e __ccf_log 2>/dev/null
function claude
    set -g __test_resumed $argv[2]
end

# Stub the picker too. When a query matches nothing, ccr falls through to `ccri` — which would
# block the whole suite waiting on fzf. That is exactly what happened when the TSV grew a
# field and this file's stub still emitted the old shape: the test did not fail, it hung.
functions -e ccri 2>/dev/null
function ccri
    set -g __test_fellback 1
    set -g __test_picker_argv $argv
end

# Keep --repo tests independent of whether this checkout is itself inside a git repository.
functions -e _claude_repo_root 2>/dev/null
function _claude_repo_root
    echo $PWD
end

# Stub the session source: two sessions in the CURRENT dir (so ccr's cd is a
# no-op), newest first — mirrors two windows resuming in the same project.
# The field order is the real one — id, title, cwd, path, mtime, branch, body — and it
# matters twice over: an out-of-date shape here silently shifts the body into another slot,
# so ccr sees no body, the query matches nothing, and it falls through to the picker.
functions -e _claude_sessions 2>/dev/null
function _claude_sessions
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' bbbb newer $PWD /x/b.jsonl 2000 main "envoy timeout"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' aaaa older $PWD /x/a.jsonl 1000 main "pants build"
end

set -e _claude_fish_last_session
set -e __test_resumed
ccr
@test "no memory: resumes the newest session" "$__test_resumed" = bbbb
@test "ccr records the session it resumed" "$_claude_fish_last_session" = bbbb

set -g _claude_fish_last_session aaaa
set -e __test_resumed
ccr
@test "with memory: resumes THIS shell's session, not the newest" "$__test_resumed" = aaaa

set -g _claude_fish_last_session zzzz
set -e __test_resumed
ccr
@test "stale memory (session gone) falls back to newest" "$__test_resumed" = bbbb

# An explicit query must still resolve (regression: `string contains` is not a
# real fish subcommand) and win over the remembered session.
set -g _claude_fish_last_session bbbb
set -e __test_resumed
ccr older
@test "query matches literally and beats memory" "$__test_resumed" = aaaa

# Search must reach the transcript, not just the title — this is what pins the body
# to its field. Neither term below appears in any title.
set -e __test_resumed
ccr pants
@test "query matches the transcript body" "$__test_resumed" = aaaa
set -e __test_resumed
ccr envoy
@test "query matches the newest body too" "$__test_resumed" = bbbb

# And prove the fallback is reachable, so the stub above is doing real work: a query that
# matches nothing must hand over to the picker rather than resume something arbitrary.
set -e __test_resumed
set -e __test_fellback
ccr definitelynothinghere
@test "an unmatched query falls through to the picker" "$__test_fellback" = 1
@test "an unmatched query resumes nothing on its own" "$__test_resumed" = ""

set -e __test_picker_argv
ccr --repo definitelynothinghere 2>/dev/null
@test "the fallback preserves repo scope" (string join ' ' -- $__test_picker_argv) = "--repo definitelynothinghere"

# --- the shell comes back ----------------------------------------------------
# Claude is launched in the session's directory because it has no flag for one, but the shell must
# not be left there: that is a side effect nobody asked for, and now more often a worktree buried
# under .claude/worktrees, since the recorded cwd is the current one rather than where the session
# started. Measured through a pty: fish skips the rest of a function when the foreground child is
# KILLED by a signal, but runs it when the child catches SIGINT and exits later — which is what
# Claude Code does with ctrl-c, so the restore holds in the normal path.
set -l cdir (mktemp -d)
mkdir -p "$cdir/lavoro" "$cdir/partenza"
# The stub above deliberately reports $PWD as the session cwd, which makes ccr's cd a no-op; this
# needs the opposite. Globals, because a function cannot see its caller's locals — that is also
# why the launch log is not just "$cdir/…".
set -g __ccf_work "$cdir/lavoro"
set -g __ccf_log "$cdir/launched-in"
function _claude_sessions
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 5111 prova $__ccf_work "$__ccf_work/x.jsonl" 3000 main prova
end
function claude
    echo "$PWD" >"$__ccf_log"
    return 3
end
set -e _claude_fish_last_session
cd "$cdir/partenza"
ccr --all >/dev/null 2>&1
set -l rc $status
@test "claude is launched in the session's directory" (cat "$__ccf_log") = "$cdir/lavoro"
@test "the shell is put back where it started" "$PWD" = "$cdir/partenza"
@test "and claude's exit status survives the trip" $rc -eq 3
functions -e claude
set -e __ccf_log
set -e __ccf_work
cd /
rm -rf "$cdir"

# --- ccr widens instead of saying "no sessions" ------------------------------
# The bug this fixes, reported from inside a worktree: the session you are in is filed under the
# directory it was STARTED in, so the folder you are working in holds no transcript and ccr said
# there was nothing at all. The stub answers only for `--under`, which is exactly the asymmetry.
set -l xdir (mktemp -d)
mkdir -p "$xdir/here"
set -g __ccf_work2 "$xdir/here"
set -g __ccf_log2 "$xdir/launched"
functions -e _claude_sessions
function _claude_sessions
    contains -- --under $argv; or return 0
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 6111 spostata $__ccf_work2 "$__ccf_work2/x.jsonl" 4000 main corpo
end
functions -e _claude_widen_root
function _claude_widen_root
    echo $__ccf_work2
end
function claude
    echo "$PWD" >"$__ccf_log2"
    return 0
end
set -e _claude_fish_last_session
cd "$xdir"
# stderr to a file: `(ccr 2>&1 >/dev/null)` came back empty here, and a captured-output idiom
# that silently yields nothing is worse than one extra file.
ccr 2>"$xdir/err" >/dev/null
set -l widen_err (cat "$xdir/err")
@test "ccr says it is widening rather than failing" (string match -q '*nothing filed under this folder*' -- "$widen_err"; and echo yes; or echo no) = yes
@test "and it resumes the session it found" (cat "$__ccf_log2") = "$xdir/here"
functions -e claude
functions -e _claude_sessions
functions -e _claude_widen_root
set -e __ccf_work2
set -e __ccf_log2
cd /
rm -rf "$xdir"
