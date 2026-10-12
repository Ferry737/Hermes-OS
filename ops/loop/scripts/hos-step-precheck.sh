#!/bin/bash
# Pre-run gate for the nightly hos-step job. Runs before the agent wakes.
# Last stdout line must be {"wakeAgent": ...}. Installed by ops/loop/install.sh,
# which replaces @REPO@ with the absolute repo path.
set -u
REPO="@REPO@"
STOP="$HOME/.hermes/HERMES_OS_STOP"
STAMP="$HOME/.hermes/hos-step.last"
BRANCH="hermes/loop"

skip() { printf '{"wakeAgent": false, "reason": "%s"}\n' "$1"; exit 0; }

# Kill switch: touch ~/.hermes/HERMES_OS_STOP to stop every loop job.
[ -e "$STOP" ] && skip "kill switch present"

# At most one step per calendar day, even if someone runs the job by hand twice.
TODAY=$(date +%F)
[ "$(cat "$STAMP" 2>/dev/null)" = "$TODAY" ] && skip "already ran today"

cd "$REPO" 2>/dev/null || { echo "repo not found at $REPO"; exit 1; }

# Never start on a dirty tree: that means a previous run or a human left work.
if [ -n "$(git status --porcelain)" ]; then
  echo "working tree is dirty; refusing to start. Run: cd $REPO && git status"
  exit 1
fi

git fetch -q origin 2>/dev/null || true
if git rev-parse -q --verify "$BRANCH" >/dev/null; then
  git switch -q "$BRANCH" || { echo "cannot switch to $BRANCH"; exit 1; }
elif git rev-parse -q --verify "origin/$BRANCH" >/dev/null; then
  git switch -q -c "$BRANCH" --track "origin/$BRANCH" || exit 1
else
  git switch -q -c "$BRANCH" || exit 1
fi

# Red secrets gate = do not wake the agent; the error alert reaches Ferry.
if ! OUT=$(sh ops/gates/secrets.sh 2>&1); then
  echo "$OUT" | tail -n 5
  exit 1
fi

NEXT=$(grep -E '^- \[ \] \*\*Q[0-9]+' ops/loop/QUEUE.md \
  | grep -vE 'needs-(ferry|claude)' | head -n1 || true)
[ -z "$NEXT" ] && skip "queue empty"

echo "$TODAY" > "$STAMP"
ITEM=$(printf '%s' "$NEXT" | sed -E 's/^- \[ \] \*\*([^*]*)\*\*.*/\1/' | tr -d '"\\')
printf '{"wakeAgent": true, "context": {"branch": "%s", "next_item": "%s"}}\n' "$BRANCH" "$ITEM"
