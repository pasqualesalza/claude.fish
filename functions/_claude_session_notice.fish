# A one-line mailbox between an action and the picker's header. fzf's execute() has no
# usable output channel — stderr goes nowhere and stdout is wiped by the redraw — so an
# action leaves its outcome here and `transform-header` picks it up. Consuming clears it,
# which is what makes a message last until the next action instead of forever.
function _claude_session_notice --description "Record or consume the picker's one-line status notice"
    argparse s/set c/consume -- $argv; or return 1
    set -l f (_claude_state_dir)/notice

    if set -q _flag_set
        mkdir -p (path dirname "$f"); or return 1
        # Collapse to a single line: this ends up as an fzf header, and a stray newline
        # would push the list down. NOT a pipe — `string replace` reading stdin treats
        # each line as its own record, so an embedded newline is a separator it never
        # sees and never replaces. Operating on the argument is what makes it work.
        set -l line (string join ' ' -- $argv | string collect)
        string replace -ra '[\r\n\t]+' ' ' -- "$line" >"$f"
        return 0
    end

    test -f "$f"; or return 1
    cat "$f"
    rm -f "$f"
    return 0
end
