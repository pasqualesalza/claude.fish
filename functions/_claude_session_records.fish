# Metadata records (title, branch, last prompt) live anywhere in the file, while
# the interesting conversation is at the recent end — so grep the former out and tail the
# latter, instead of parsing megabytes of transcript.
#
# The grep used to scan the whole file, which is what made the preview slow on a large
# session: 531ms of a 586ms render on an 84MB transcript, dwarfing every other stage. Only
# the LAST matching record is ever used, so scanning the recent tail finds the same answer —
# with a full-file fallback for the rare session whose title was set early and never touched
# since. Below the window size this is byte-for-byte the old behaviour.
function _claude_session_records --description "Emit the jsonl records worth previewing for a session"
    set -l path $argv[1]
    set -l lines 400
    test -n "$argv[2]"; and set lines $argv[2]
    set -l window 4194304

    set -l pat '"type":"(custom-title|ai-title|agent-name|last-prompt)"'
    # tail -c can start mid-line; that partial line would be invalid JSON and would take
    # `jq -s` down with it, so drop the first line of the window.
    set -l meta (tail -c $window "$path" | tail -n +2 | grep -aE $pat)
    if test (count $meta) -eq 0
        set meta (grep -aE $pat "$path")
    end
    test (count $meta) -gt 0; and printf '%s\n' $meta

    tail -n $lines "$path"
end
