# The one definition of "this user turn is machinery, not something you typed".
#
# Claude Code injects its own bookkeeping into the transcript as ordinary `user` records, and
# does NOT flag them isMeta — so that field cannot separate them from a real prompt. They arrive
# as XML-ish blocks, and in a preview they are noise: a wall of <task-id> and <output-file>
# where a question should be, or a slash command's own plumbing as a session's title.
#
# The tag list is measured, not guessed. Counting what actually opens a user message across
# every transcript on disk:
#
#   command-name 35 · command-message 35 · command-args 33 · local-command-caveat 32
#   local-command-stdout 23 · tool-use-id 11 · task-notification 11 · task-id 11
#   summary 11 · status 11 · output-file 11 · system-reminder 3
#
# Two lessons in that table. `local-command-caveat` was missing from the first version, so a
# third of the injected turns still leaked. And a task notification is split across SEVERAL
# text records, which is why matching only its opening tag was not enough — <task-id>,
# <output-file>, <status> and <summary> each start a record of their own.
#
# `usage`, `result` and `note` also appear, twice each, and are deliberately NOT listed: those
# are ordinary words, and a message that genuinely opens with one should still be shown.
#
# Used by _claude_sessions (for the list title), _claude_session_head (the preview title) and
# _claude_session_markdown (the turns). It lived in all three as a copy until one of them fell
# behind.
function _claude_injected_re --description "Regex matching a user turn that is Claude Code machinery, not a prompt"
    echo '^[[:space:]]*</?(task-notification|task-id|tool-use-id|output-file|status|summary|system-reminder|command-name|command-message|command-args|local-command-[a-z]+)>'
end
