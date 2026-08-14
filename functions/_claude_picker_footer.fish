function _claude_picker_footer --description "Key hints for the ccri picker's footer bar"
    argparse t/trash r/read -- $argv 2>/dev/null

    # Read mode has its own hints: the scroll keys only mean something there, and the way
    # back out is not obvious enough to leave unsaid.
    if set -q _flag_read
        echo 'shift-↑↓ scroll · alt-↑↓ page · ctrl-/ back to list · enter resume'
        return 0
    end
    if set -q _flag_trash
        echo 'enter restore · ctrl-o read · ctrl-/ preview · esc quit'
    else
        echo 'enter resume · ctrl-x trash · ctrl-p pin · ctrl-o read · ctrl-/ preview · esc quit'
    end
end
