# Trim to a visible budget, marking the cut with … so a row ends on purpose rather than
# disappearing under the pane border.
function _claude_fit --description "Truncate a string to N display columns, adding … when cut"
    set -l s $argv[1]
    set -l n $argv[2]
    string match -qr '^[0-9]+$' -- "$n"; or begin
        echo $s
        return
    end
    test $n -lt 1; and begin
        echo ''
        return
    end
    if test (string length -- "$s") -gt $n
        echo (string sub -l (math $n - 1) -- "$s")…
    else
        echo $s
    end
end
