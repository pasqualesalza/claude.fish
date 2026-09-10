# The jq definitions both preview renderers share, so the mdcat path and the no-dependency
# fallback can never disagree about what you are looking at: how a message is cut down to a
# budget, and when a turn happened.
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
function _claude_clip_jq --description "jq definitions shared by both preview renderers"
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
      # When a turn happened. Just the clock inside one day; the date as well on the first turn of
      # a new one, which is the convention every chat client settled on — a bare 14:05 on a
      # three-week-old session says nothing. Two SPACES separate it from the role, never a middle
      # dot: the frame pass is awk, the awk on CI is mawk, and mawk counts bytes, so a multi-byte
      # separator would have to be measured in bytes there.
      # (No apostrophes in this comment on purpose: the whole program is a single-quoted fish
      # string, and one apostrophe ends it — which is exactly how this edit failed the first time.)
      #
      # Local time via strflocaltime. On jq 1.6 that is an hour off during DST (measured: 11:00 for
      # an 08:00Z August instant, against 10:00 on 1.7 and later) — the times are right from 1.7.
      # [.] rather than an escaped dot: a backslash has to survive BOTH fish single quotes and jq
      # string parsing, and what reaches jq is then an invalid JSON escape. Same trick as the
      # [*][*] in the fallback renderer.
      def epoch: if . == null or . == "" then null else (sub("[.][0-9]+Z$"; "Z") | fromdateiso8601) end;
      def when($prev):
        (.ts | epoch) as $e
        | if $e == null then ""
          else ($e | strflocaltime("%Y-%m-%d")) as $day
            | ($prev | epoch) as $pe
            | (if $pe == null then true else (($pe | strflocaltime("%Y-%m-%d")) != $day) end) as $newday
            | if $newday then ($e | strflocaltime("%d %b %H:%M")) else ($e | strflocaltime("%H:%M")) end
          end;

'
end
