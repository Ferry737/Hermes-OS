#!/bin/sh
# Circuit breaker. Counts gate evaluations (≈ one per goal turn boundary) and
# goes red once the cap is hit. A red gate that exhausts its retries auto-pauses
# the goal, so this is the hard stop on a runaway autonomous loop.
#
# Reset between sessions:  rm ops/.budget
# Raise the cap:           BUDGET_MAX=120 in the environment
set -eu
cd "$(dirname "$0")/../.."

MAX="${BUDGET_MAX:-60}"
F=ops/.budget
[ -f "$F" ] || echo 0 > "$F"

N=$(cat "$F")
N=$((N + 1))
echo "$N" > "$F"

if [ "$N" -gt "$MAX" ]; then
  echo "BUDGET EXHAUSTED: $N/$MAX turn boundaries used."
  echo "The loop has run longer than budgeted. Review the work before continuing."
  echo "To continue anyway: rm ops/.budget && /goal resume"
  exit 1
fi

echo "budget ok: $N/$MAX"
