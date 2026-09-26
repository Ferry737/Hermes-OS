#!/bin/sh
# Checks the live Orchestra service. Staged by orchestra/ops/.phase:
#   0 = nothing deployed (skipped)   2 = deployed (health, auth guard and serve rule enforced)
# The loop raises the phase in task P5.5. It may never lower it.
set -eu
cd "$(dirname "$0")/../../.."
PHASE=0; [ -f orchestra/ops/.phase ] && PHASE=$(cat orchestra/ops/.phase)
[ "$PHASE" -lt 2 ] && { echo "phase $PHASE: Orchestra not deployed yet, smoke skipped"; exit 0; }

fail() { echo "SMOKE FAIL: $1"; exit 1; }
URL=http://127.0.0.1:8790

curl -fsS --max-time 5 "$URL/healthz" | grep -q '"ok": *true' || fail "/healthz not ok. Is uvicorn running? (orchestra/deploy.sh --start-only)"

CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL/api/models")
[ "$CODE" = "401" ] || fail "/api/models without identity returned $CODE, expected 401: the identity guard is off"

OWNER=$(grep '^ORCHESTRA_OWNER_LOGIN=' /opt/data/orchestra/orchestra.env 2>/dev/null | cut -d= -f2-)
[ -n "$OWNER" ] || fail "ORCHESTRA_OWNER_LOGIN missing from /opt/data/orchestra/orchestra.env"
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "Tailscale-User-Login: $OWNER" "$URL/api/models")
[ "$CODE" = "200" ] || fail "/api/models as owner returned $CODE, expected 200 (gateway down or key wrong?)"

/opt/data/bin/tailscale --socket=/opt/data/.tailscale/tailscaled.sock serve status 2>/dev/null | grep -q '8790' \
  || fail "no tailscale serve rule points at 8790"

echo "smoke gate clean (phase $PHASE)"
