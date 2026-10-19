set -l here (status dirname)
for f in "$here"/../functions/_claude_*.fish
    source $f
end
# The first `complete -C "claude …"` autoloads whatever claude.fish is INSTALLED, which would
# replace the one under test. Trigger that load now, then source ours over it.
complete -C "claude " >/dev/null
source "$here/../completions/claude.fish"

# `-r` is claude's own short form of `--resume`; without it `claude -r <TAB>` offered subcommands.
functions -e _claude_sessions
function _claude_sessions
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 7aaa qui $PWD /x/a.jsonl 2000 main corpo
end
@test "-r completes session ids like --resume" (complete -C "claude -r " | string split -f1 \t) = 7aaa
@test "and the title rides along as the description" (complete -C "claude --resume " | string split -f2 \t) = qui

# Global, like `claude --resume` itself: the stub answers only for `--all`.
function _claude_sessions
    contains -- --all $argv; or return 0
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 7bbb altrove /elsewhere /x/b.jsonl 2000 main corpo
end
@test "it offers sessions from every project" (complete -C "claude --resume " | string split -f1 \t) = 7bbb

functions -e _claude_sessions
