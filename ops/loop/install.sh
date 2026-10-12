#!/bin/bash
# Installs the Hermes OS loop into Hermes Agent on this VPS.
#   bash ops/loop/install.sh            # from the repo root
# Optional env:
#   DELIVER=telegram   where reports go (default: local -> ~/.hermes/cron/output/)
#   MORNING="30 5 * * *"   cron expression in the VPS clock (check: timedatectl)
#   STEP="0 1 * * *"
# Safe to run twice: existing jobs with the same name are left alone.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
HH="${HERMES_HOME:-$HOME/.hermes}"
DELIVER="${DELIVER:-local}"
MORNING="${MORNING:-30 5 * * *}"
STEP="${STEP:-0 1 * * *}"

command -v hermes >/dev/null || { echo "hermes CLI not found"; exit 1; }
[ -f "$REPO/ops/loop/QUEUE.md" ] || { echo "run from the Hermes-OS repo"; exit 1; }

mkdir -p "$HH/skills/ops/hermes-os-loop" "$HH/scripts"
cp "$REPO/ops/loop/skills/hermes-os-loop/SKILL.md" "$HH/skills/ops/hermes-os-loop/SKILL.md"
for s in hos-step-precheck.sh hos-morning-precheck.sh; do
  sed "s#@REPO@#$REPO#g" "$REPO/ops/loop/scripts/$s" > "$HH/scripts/$s"
  chmod 700 "$HH/scripts/$s"
done
echo "skill and scripts installed"

exists() { hermes cron list 2>/dev/null | grep -qiw "$1"; }

if exists hos-morning; then
  echo "hos-morning already exists, skipped"
else
  hermes cron create "$MORNING" \
    "Run the morning job from the hermes-os-loop skill. Read-only: do not edit, commit or install anything. Use the context from the pre-run script for health facts. Answer in simple Persian." \
    --name hos-morning --skill hermes-os-loop --workdir "$REPO" \
    --script hos-morning-precheck.sh --deliver "$DELIVER"
fi

if exists hos-step; then
  echo "hos-step already exists, skipped"
else
  hermes cron create "$STEP" \
    "Run the night job from the hermes-os-loop skill: exactly one item from ops/loop/QUEUE.md (the pre-run context names it), on branch hermes/loop, then stop. Answer in simple Persian." \
    --name hos-step --skill hermes-os-loop --workdir "$REPO" \
    --script hos-step-precheck.sh --deliver "$DELIVER"
fi

hermes cron list
echo
echo "Test now:   hermes cron run hos-morning"
echo "Stop all:   touch $HH/HERMES_OS_STOP      (resume: rm $HH/HERMES_OS_STOP)"
