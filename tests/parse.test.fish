set -l here (status dirname)
set -gx CLAUDE_FISH_PROJECTS_ROOT "$here/fixtures/projects"
source "$here/../functions/_claude_sessions.fish"

set -l rows (_claude_sessions --all)

@test "skips sidechain-only sessions" (count $rows) -eq 1

set -l p (string split \t -- $rows[1])

@test "uses the summary as the title" "$p[2]" = "Envoy LB timeout fix"
@test "captures the session cwd" "$p[3]" = "/tmp/proj"
@test "indexes the transcript body" (string match -q '*envoy timeout*' (string lower -- "$p[5]"); and echo yes) = yes
