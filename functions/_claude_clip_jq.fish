# The jq definitions that cut a message down to a budget, shared by both renderers so the
# mdcat path and the no-dependency fallback can never disagree about what you are looking at.
#
# Cutting at an exact character count lands mid-sentence, mid-list and mid-code — a message
# stops on "e la riga di sot" and reads as damage rather than as a preview. So the cut walks
# whole units and steps down only when a single unit will not fit:
#
#   1. whole BLOCKS — paragraphs, lists, fenced code, split on blank lines outside a fence
#   2. whole LINES  — for the one block that is itself over budget (a long code listing)
#   3. WORDS        — for the one line that is over budget (a wall-of-text paragraph)
#
# Which end is kept is the caller's choice: the pane is anchored on the end of the
# conversation, so the last turn keeps its tail and the earlier ones their head.
#
# `balance` repairs the fences afterwards, and which end was cut decides how: dropping the
# START of a message can leave a code block already open, which needs an opening fence, while
# dropping the END needs a closing one. Without it, one unbalanced fence makes a markdown
# renderer read every LATER turn as code too — markdown has no turn boundaries — and the rest
# of the pane arrives as literal ** and ## headings.
function _claude_clip_jq --description "jq definitions for clipping a message at block boundaries"
    echo '
      def _blocks:
        split("\n")
        | reduce .[] as $l ({cur: [], out: [], fence: false};
            if ($l | test("^ {0,3}```"))
            then {cur: (.cur + [$l]), out: .out, fence: (.fence | not)}
            elif ((.fence | not) and ($l | test("^[ \t]*$")))
            then {cur: [], out: (if (.cur|length) > 0 then .out + [.cur | join("\n")] else .out end), fence: false}
            else {cur: (.cur + [$l]), out: .out, fence: .fence}
            end)
        | .out + (if (.cur|length) > 0 then [.cur | join("\n")] else [] end);
      def _cutchars($tail; $b):
        if $tail then (.[(length - $b):] | sub("^[^ \n]*[ \n]"; ""))
        else (.[0:$b] | sub("[ \n][^ \n]*$"; "")) end;
      def _cutlines($tail; $b):
        (split("\n")) as $ls
        | (if $tail then ($ls|reverse) else $ls end) as $ord
        | (reduce $ord[] as $l ({keep: [], used: 0, done: false};
              if .done then . elif ((.used + ($l|length) + 1) <= $b)
              then {keep: (.keep + [$l]), used: (.used + ($l|length) + 1), done: false}
              else {keep: .keep, used: .used, done: true} end) | .keep) as $keep
        | if ($keep|length) == 0 then ($ord[0] | _cutchars($tail; $b))
          else ((if $tail then ($keep|reverse) else $keep end) | join("\n")) end;
      def _cutblocks($tail; $b):
        _blocks as $bs
        | (if $tail then ($bs|reverse) else $bs end) as $ord
        | (reduce $ord[] as $x ({keep: [], used: 0, done: false};
              if .done then . elif ((.used + ($x|length) + 2) <= $b)
              then {keep: (.keep + [$x]), used: (.used + ($x|length) + 2), done: false}
              else {keep: .keep, used: .used, done: true} end) | .keep) as $keep
        | if ($keep|length) == 0 then ($ord[0] | _cutlines($tail; $b))
          else ((if $tail then ($keep|reverse) else $keep end) | join("\n\n")) end;
      def balance($tail):
        . as $t
        | if (($t | split("\n") | map(select(test("^ {0,3}```"))) | length) % 2) == 0 then $t
          elif $tail then "```\n" + $t
          else $t + "\n```" end;
      def clipped($tail; $b): _cutblocks($tail; $b) | balance($tail);
'
end
