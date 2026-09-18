#!/bin/sh
# Refuse to let the loop commit infrastructure detail or credentials.
# An autonomous agent writing docs about your own VPS will paste real values in
# sooner or later. This makes that a red gate instead of a public repo.
set -eu
cd "$(dirname "$0")/../.."

FILES=$(git ls-files 2>/dev/null || true)
[ -n "$FILES" ] || { echo "no tracked files yet"; exit 0; }

FOUND=0
report() { echo "LEAK [$1]: $2"; FOUND=1; }

# Credentials and key material.
for f in $FILES; do
  [ -f "$f" ] || continue
  case "$f" in ops/gates/secrets.sh) continue ;; esac

  grep -nE 'BEGIN (RSA|OPENSSH|EC|PGP) PRIVATE KEY' "$f" 2>/dev/null \
    && report "private key" "$f"
  grep -nE '(gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-)' "$f" 2>/dev/null \
    && report "api token" "$f"
  grep -nE 'HERMES_DASHBOARD_BASIC_AUTH_(PASSWORD|SECRET)[[:space:]]*=[[:space:]]*[^<$"'"'"'[:space:]]' "$f" 2>/dev/null \
    && report "dashboard credential" "$f"
  grep -nE 'tskey-[A-Za-z0-9-]+' "$f" 2>/dev/null \
    && report "tailscale auth key" "$f"

  # Real infrastructure identifiers. Placeholders are the point, so anything
  # wrapped in <> or named *example*/<tailnet> is fine.
  grep -noE '\b[0-9]{1,3}(\.[0-9]{1,3}){3}\b' "$f" 2>/dev/null \
    | grep -vE ':(0\.0\.0\.0|127\.0\.0\.1|255\.255\.255\.255|1\.2\.3\.4|0(\.0)*)$' \
    && report "ip address" "$f"
  grep -nE '[a-z0-9-]+\.[a-z0-9-]+\.ts\.net' "$f" 2>/dev/null \
    | grep -vE '<|example|tailnet-name|YOUR' \
    && report "tailnet hostname" "$f"
done

if [ "$FOUND" -ne 0 ]; then
  echo
  echo "Replace each value with a placeholder (<tailnet>, <VPS_IP>, <password>)."
  echo "Real values belong in ~/.hermes/.env on the VPS, never in this repo."
  exit 1
fi

echo "secrets gate clean"
