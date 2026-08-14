set -l here (status dirname)
set -gx CLAUDE_FISH_PROJECTS_ROOT "$here/fixtures/projects"
# By glob, not by list. A helper left off a list still resolves from the user's installed
# plugin — or, for a brand-new one, resolves to nothing at all: _claude_injected_re went
# missing here and its regex reached jq as an empty string, which matches everything, so every
# user message was filtered out and the title fell back to "(untitled)".
for f in "$here"/../functions/_claude_*.fish
    source $f
end

set -l rows (_claude_sessions --all)

# 3 fixtures: 11111111 (custom-title), 22222222 (sidechain-only), 33333333 (mixed).
@test "drops sidechain-only, keeps normal + mixed" (count $rows) -eq 2

# Find rows by id prefix so the assertions don't depend on mtime ordering.
set -l p (string split \t -- (printf '%s\n' $rows | grep '^11111111'))
@test "emits id/title/cwd/path/mtime/branch/body" (count $p) -eq 7
@test "custom-title (/rename) wins, with ✎ marker" "$p[2]" = "✎ envoy work"
@test "captures the session cwd" "$p[3]" = /tmp/proj
@test "carries the mtime for the age column" (string match -qr '^[0-9]+$' -- "$p[5]"; and echo yes) = yes
@test "carries the git branch for the list row" "$p[6]" = main
@test "indexes the transcript body" (string match -q '*envoy timeout*' (string lower -- "$p[7]"); and echo yes) = yes
@test "short transcripts are not duplicated by overlapping head and tail windows" (string match -ar 'Fix the envoy timeout' -- "$p[7]" | count) -eq 1

# M2: a file with both a sidechain turn and normal turns must survive (with its title).
@test "keeps mixed sidechain+main session" (printf '%s\n' $rows | grep '^33333333' | grep -c 'mixed session') -ge 1

# A session opened with a slash command has the command XML as its first user message, and it
# is NOT flagged isMeta — so without filtering, the list titled such sessions
# "<command-name>/clear</command-name> …". Fall through to the next real message instead.
set -l cdir (mktemp -d)
mkdir -p "$cdir/projects/enc"
printf '%s\n' \
    '{"type":"user","cwd":"/tmp/p","message":{"role":"user","content":[{"type":"text","text":"<command-name>/clear</command-name> <command-message>clear</command-message>"}]}}' \
    '{"type":"user","cwd":"/tmp/p","message":{"role":"user","content":[{"type":"text","text":"la vera prima domanda"}]}}' >"$cdir/projects/enc/44444444-4444-4444-8444-444444444444.jsonl"
set -gx CLAUDE_FISH_PROJECTS_ROOT "$cdir/projects"
set -l ctitle (string split \t -- (_claude_sessions --all)[1])[2]
set -gx CLAUDE_FISH_PROJECTS_ROOT "$here/fixtures/projects"
@test "a slash-command opener is not used as the title" (string match -q '*command-name*' -- "$ctitle"; and echo leaked; or echo clean) = clean
@test "the next real message becomes the title" "$ctitle" = "la vera prima domanda"
rm -rf "$cdir"
