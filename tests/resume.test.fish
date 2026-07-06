set -l here (status dirname)
source "$here/../functions/ccr.fish"

# Stub `claude` so `--resume <id>` records the id instead of launching anything.
functions -e claude 2>/dev/null
function claude
    set -g __test_resumed $argv[2]
end

# Stub the session source: two sessions in the CURRENT dir (so ccr's cd is a
# no-op), newest first — mirrors two windows resuming in the same project.
functions -e _claude_sessions 2>/dev/null
function _claude_sessions
    printf '%s\t%s\t%s\t%s\t%s\n' bbbb newer $PWD /x/b.jsonl "body b"
    printf '%s\t%s\t%s\t%s\t%s\n' aaaa older $PWD /x/a.jsonl "body a"
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
