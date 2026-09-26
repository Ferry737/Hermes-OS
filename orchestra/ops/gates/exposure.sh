#!/bin/sh
# Red if anything on this host could be public. This enforces SPEC D4, D5 and D6 and
# the lessons of the 2026-09-24 incident. It is green on machines where nothing runs.
set -eu
cd "$(dirname "$0")/../../.."
FAIL=0
fail() { echo "EXPOSURE: $1"; FAIL=1; }

# 1. No tunnel software running (exact executable names, so grep never matches itself).
if ps -eo comm 2>/dev/null | grep -qxE 'cloudflared|ngrok|localtunnel'; then
  fail "tunnel process running: $(ps -eo pid,comm | grep -E 'cloudflared|ngrok|localtunnel' | tr '\n' ' ')"
fi

# 2. Gateway (8642), JARVIS (8788) and Orchestra (8790) listen on loopback only.
#    /proc/net/tcp columns: local_address is $2 (HEXIP:HEXPORT), state is $4 (0A = LISTEN).
for pair in 21C2:8642 2254:8788 2256:8790; do
  hex=${pair%%:*}; port=${pair##*:}
  for f in /proc/net/tcp /proc/net/tcp6; do
    [ -r "$f" ] || continue
    bad=$(awk -v p=":$hex" '$4=="0A" && substr($2, length($2)-4)==p {
            split($2, a, ":");
            if (a[1] != "0100007F" && a[1] != "00000000000000000000000001000000") print a[1] }' "$f")
    [ -z "$bad" ] || fail "port $port listens on a non-loopback address ($f)"
  done
done

# 3. Tailscale Funnel (public internet) must be off.
TS=/opt/data/bin/tailscale; SOCK=/opt/data/.tailscale/tailscaled.sock
if [ -x "$TS" ] && [ -S "$SOCK" ]; then
  if "$TS" --socket="$SOCK" serve status 2>/dev/null | grep -qi 'funnel on'; then
    fail "Tailscale Funnel is on: a service is public"
  fi
fi

# 4. No secrets in anything the browser can download.
if [ -d orchestra/web ] && grep -rqE 'API_SERVER_KEY|hsk_[A-Za-z0-9_-]{8,}|sk-[A-Za-z0-9_-]{20,}' orchestra/web; then
  fail "secret-like string in orchestra/web: $(grep -rlE 'API_SERVER_KEY|hsk_|sk-' orchestra/web | tr '\n' ' ')"
fi

[ "$FAIL" -eq 0 ] || { echo "Fix exposure before any other work (PLAYBOOK rule 6)."; exit 1; }
echo "exposure gate clean"
