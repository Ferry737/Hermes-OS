#!/bin/sh
# Circuit breaker for the Orchestra loop. Counts gate evaluations (about one per turn)
# and goes red at the cap, which pauses the goal. Reset: rm orchestra/ops/.budget
set -eu
cd "$(dirname "$0")/../../.."
MAX="${ORCHESTRA_BUDGET_MAX:-60}"
F=orchestra/ops/.budget
[ -f "$F" ] || echo 0 > "$F"
N=$(( $(cat "$F") + 1 ))
echo "$N" > "$F"
if [ "$N" -gt "$MAX" ]; then
  echo "BUDGET EXHAUSTED: $N/$MAX turns. Review the diff, then: rm orchestra/ops/.budget && /goal resume"
  exit 1
fi
echo "budget ok: $N/$MAX"
