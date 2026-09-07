#!/usr/bin/env bash
# Measure how often each guard would fire, against YOUR transcripts.
#
# claim becomes testable without anyone disclosing anything: run it and get your
# own numbers. If a guard fires on 30% of your messages it is noise for you,
# whatever it did for the author.
#
# Nothing leaves the machine and no transcript text is printed unless you pass
# --sample, which exists so you can confirm a pattern matches what you expect.
#
#   corpus-stats.sh                 every guard, default transcript root
#   corpus-stats.sh --dir <path>    a different root
#   corpus-stats.sh --sample N      print N matching excerpts per pattern
#   corpus-stats.sh --since <date>  only sessions modified since (date -d syntax)
set -uo pipefail
DIR="$HOME/.claude/projects"; SAMPLE=0; SINCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)    DIR="$2"; shift 2 ;;
    --sample) SAMPLE="$2"; shift 2 ;;
    --since)  SINCE="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -d "$DIR" ] || { echo "no transcript directory at $DIR (use --dir)" >&2; exit 2; }

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$root/.claude/hooks/banned-patterns.sh" 2>/dev/null || {
  echo "cannot source banned-patterns.sh" >&2; exit 2; }

if [ -n "$SINCE" ]; then
  mapfile -t FILES < <(find "$DIR" -name '*.jsonl' -newermt "$SINCE" 2>/dev/null)
else
  mapfile -t FILES < <(find "$DIR" -name '*.jsonl' 2>/dev/null)
fi
[ "${#FILES[@]}" -gt 0 ] || { echo "no .jsonl transcripts under $DIR" >&2; exit 2; }

# Assistant text only. A guard that fires on the user's own words is measuring the
# wrong thing, and tool output would inflate every count with file contents.
TXT=$(mktemp); trap 'rm -f "$TXT"' EXIT
python3 - "$TXT" "${FILES[@]}" <<'PY'
import json, sys
out = open(sys.argv[1], "w"); n = 0
for path in sys.argv[2:]:
    try: fh = open(path, "rb")
    except OSError: continue
    for line in fh:
        if b'"assistant"' not in line: continue
        try: r = json.loads(line)
        except Exception: continue
        if r.get("type") != "assistant": continue
        c = (r.get("message") or {}).get("content")
        if isinstance(c, str): parts = [c]
        elif isinstance(c, list):
            parts = [b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text"]
        else: continue
        for p in parts:
            if p.strip():
                out.write(p.replace("\n", " ") + "\n"); n += 1
print(n, file=sys.stderr)
PY
MSGS=$(wc -l < "$TXT")

printf 'transcripts %s   assistant text blocks %s\n\n' "${#FILES[@]}" "$MSGS"
printf '%-14s %8s %8s   %s\n' class hits rate note
printf '%-14s %8s %8s   %s\n' ------------- -------- -------- ----
total=0
for v in SUP TIC SYC EST PNT HAZ CMP EDIT PAR ADV ABS BRC OFFBOX VIRT MSG DASH; do
  pat="${!v:-}"; [ -n "$pat" ] || continue
  h=$(grep -icE "$pat" "$TXT" 2>/dev/null); h=${h:-0}
  total=$((total + h))
  rate=$(awk -v h="$h" -v m="$MSGS" 'BEGIN{printf "%.2f%%", m?100*h/m:0}')
  printf '%-14s %8s %8s\n' "$v" "$h" "$rate"
  if [ "$SAMPLE" -gt 0 ] && [ "$h" -gt 0 ]; then
    grep -ioE ".{0,40}$pat.{0,30}" "$TXT" 2>/dev/null | head -"$SAMPLE" | sed 's/^/                 /'
  fi
done
# A high rate can mean the guard is noise, or that the corpus predates the rule and
# you are looking at the baseline it was written against. --since separates the two.
printf '\n%-14s %8s %8s   %s\n' TOTAL "$total" \
  "$(awk -v h="$total" -v m="$MSGS" 'BEGIN{printf "%.2f%%", m?100*h/m:0}')" \
  "counts overlap: one message can hit several classes"

echo
echo "False positives against the corpus that ships in this repo:"
NEG="$root/.claude/hooks/ban-corpus-negatives.txt"
if [ -f "$NEG" ]; then
  fp=0
  for v in SUP TIC SYC EST PNT HAZ CMP EDIT PAR ADV ABS BRC OFFBOX VIRT MSG DASH; do
    pat="${!v:-}"; [ -n "$pat" ] || continue
    n=$(grep -icE "$pat" "$NEG" 2>/dev/null); n=${n:-0}
    [ "$n" -gt 0 ] && { echo "  $v fires on $n known-good line(s)"; fp=$((fp+n)); }
  done
  [ "$fp" -eq 0 ] && echo "  none, across $(grep -vc '^#' "$NEG") known-good lines"
else
  echo "  ban-corpus-negatives.txt not found"
fi
