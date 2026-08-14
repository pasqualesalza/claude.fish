# The column budget for one list row, from a terminal width.
#
# In one place because two callers need the same answer at different moments: ccri measures
# `$COLUMNS` for the first build, because fzf's own `$FZF_COLUMNS` is still 0 while the UI is
# sizing itself — which is exactly when that build runs — and the reload command measures
# `$FZF_COLUMNS` afterwards, which is what makes a row fit again after the window is resized.
#
# 45% of the terminal, less 12: the list border takes 2, the pointer takes 2, the rest is slack.
# Under-estimating is the safe direction — a row that ends early just carries trailing spaces,
# while over-estimating lets fzf cut a word in half at the border.
function _claude_list_width --description "Column budget for a picker row, from a terminal width"
    set -l cols $argv[1]
    string match -qr '^[1-9][0-9]*$' -- "$cols"; or begin
        echo 56
        return 0
    end
    math "max(24, floor($cols * 0.45) - 12)"
end
