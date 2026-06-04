set -l here (status dirname)
set -gx CLAUDE_FISH_PROJECTS_ROOT "$here/fixtures/projects"
source "$here/../functions/_claude_sessions.fish"

set -l rows (_claude_sessions --all)

# 3 fixtures: 11111111 (custom-title), 22222222 (sidechain-only), 33333333 (mixed).
@test "drops sidechain-only, keeps normal + mixed" (count $rows) -eq 2

# Find rows by id prefix so the assertions don't depend on mtime ordering.
set -l p (string split \t -- (printf '%s\n' $rows | grep '^11111111'))
@test "custom-title (/rename) wins, with ✎ marker" "$p[2]" = "✎ envoy work"
@test "captures the session cwd" "$p[3]" = /tmp/proj
@test "indexes the transcript body" (string match -q '*envoy timeout*' (string lower -- "$p[5]"); and echo yes) = yes

# M2: a file with both a sidechain turn and normal turns must survive (with its title).
@test "keeps mixed sidechain+main session" (printf '%s\n' $rows | grep '^33333333' | grep -c 'mixed session') -ge 1
