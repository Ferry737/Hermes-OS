#!/bin/bash
# Pre-run script for hos-morning. Collects health facts so the agent does not
# have to guess them. Read-only. Installed by ops/loop/install.sh.
set -u
REPO="@REPO@"
STOP="$HOME/.hermes/HERMES_OS_STOP"
[ -e "$STOP" ] && { echo '{"wakeAgent": false, "reason": "kill switch present"}'; exit 0; }

DISK=$(df -P / | awk 'NR==2{print $5}')
MEM=$(free -m 2>/dev/null | awk '/^Mem:/{print $7" MB free of "$2" MB"}')
LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
UP=$(uptime -p 2>/dev/null || uptime)
# Listening sockets not bound to loopback. Ports only, no addresses leave the box.
PUBLIC=$(ss -tlnH 2>/dev/null | awk '{print $4}' \
  | grep -vE '^(127\.|\[::1\]|::1)' | grep -E '^(0\.0\.0\.0|\*|\[::\]|::):' \
  | sed -E 's/.*:([0-9]+)$/\1/' | sort -un | tr '\n' ' ')
NEXT=$(grep -m1 -E '^- \[ \] \*\*Q[0-9]+' "$REPO/ops/loop/QUEUE.md" 2>/dev/null \
  | sed -E 's/^- \[ \] \*\*([^*]*)\*\*.*/\1/' | tr -d '"\\')

esc() { printf '%s' "$1" | tr -d '"\\\n'; }
printf '{"wakeAgent": true, "context": {"disk_used": "%s", "memory": "%s", "load": "%s", "uptime": "%s", "public_ports": "%s", "next_queue_item": "%s"}}\n' \
  "$(esc "$DISK")" "$(esc "$MEM")" "$(esc "$LOAD")" "$(esc "$UP")" "$(esc "$PUBLIC")" "$(esc "$NEXT")"
