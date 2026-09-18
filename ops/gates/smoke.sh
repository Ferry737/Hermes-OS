#!/bin/sh
# End-to-end check against the live dashboard. Staged by ops/.phase so it is
# green before there is anything to check, and strict once the plugin ships.
#
# ops/.phase contents:  0 = nothing deployed   (all checks skipped)
#                       1 = dashboard running  (auth + reachability enforced)
#                       3 = plugin deployed    (plugin routes enforced)
#
# The agent advances the phase as it completes plan phases. It may never lower it.
set -eu
cd "$(dirname "$0")/../.."

PHASE=0
[ -f ops/.phase ] && PHASE=$(cat ops/.phase)
URL="${HERMES_DASHBOARD_URL:-http://127.0.0.1:9119}"

[ "$PHASE" -lt 1 ] && { echo "phase $PHASE: nothing deployed yet, smoke skipped"; exit 0; }

fail() { echo "SMOKE FAIL: $1"; exit 1; }

command -v curl >/dev/null 2>&1 || fail "curl not installed"

# 1. Dashboard answers at all.
curl -fsS --max-time 10 "$URL/api/status" >/tmp/.smoke-status 2>/dev/null \
  || fail "$URL/api/status unreachable — is hermes-dashboard.service running?"

# 2. The auth gate is actually engaged. This is finding #1 from the review:
#    a loopback bind behind a proxy can leave the dashboard unauthenticated.
if command -v jq >/dev/null 2>&1; then
  AUTH=$(jq -r '.auth_required // "missing"' /tmp/.smoke-status)
  [ "$AUTH" = "true" ] || fail "auth_required=$AUTH — the dashboard is serving the tailnet with no auth gate"
  jq -e '.auth_providers | index("basic")' /tmp/.smoke-status >/dev/null \
    || fail "basic auth provider not advertised — check HERMES_DASHBOARD_BASIC_AUTH_* in ~/.hermes/.env"
else
  grep -q '"auth_required"[[:space:]]*:[[:space:]]*true' /tmp/.smoke-status \
    || fail "auth_required is not true"
fi

[ "$PHASE" -lt 3 ] && { echo "phase $PHASE: dashboard healthy and gated, plugin checks skipped"; exit 0; }

# 3. Plugin routes exist and are behind the auth gate.
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
       "$URL/api/plugins/hermes-cockpit/summary")
[ "$CODE" = "401" ] || fail "unauthenticated /summary returned $CODE, expected 401"

# 4. Theme file is installed and parses.
[ -f "$HOME/.hermes/dashboard-themes/hermes-cockpit.yaml" ] \
  || fail "theme file missing from ~/.hermes/dashboard-themes/"
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' \
    "$HOME/.hermes/dashboard-themes/hermes-cockpit.yaml" \
    || fail "theme YAML does not parse"
fi

# 5. Plugin manifest is installed.
[ -f "$HOME/.hermes/plugins/hermes-cockpit/dashboard/manifest.json" ] \
  || fail "plugin manifest missing from ~/.hermes/plugins/"

echo "smoke gate clean (phase $PHASE)"
