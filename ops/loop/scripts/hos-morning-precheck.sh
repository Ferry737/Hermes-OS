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
NEXT=$(git -C "$REPO" show hermes/loop:ops/loop/QUEUE.md 2>/dev/null \
  | grep -m1 -E '^- \[ \] \*\*Q[0-9]+' \
  | sed -E 's/^- \[ \] \*\*([^*]*)\*\*.*/\1/' | tr -d '"\\')

# Persian (Jalali) date, computed here so the model never guesses it.
JDATE=$(python3 - <<'PY'
import datetime
t = datetime.date.today()
gy, gm, gd = t.year, t.month, t.day
g_d_m = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
gy2 = gy + 1 if gm > 2 else gy
days = 355666 + 365 * gy + (gy2 + 3) // 4 - (gy2 + 99) // 100 + (gy2 + 399) // 400 + gd + g_d_m[gm - 1]
jy = -1595 + 33 * (days // 12053); days %= 12053
jy += 4 * (days // 1461); days %= 1461
if days > 365:
    jy += (days - 1) // 365; days = (days - 1) % 365
jm = 1 + days // 31 if days < 186 else 7 + (days - 186) // 30
jd = 1 + (days % 31 if days < 186 else (days - 186) % 30)
print(f"{jy}-{jm:02d}-{jd:02d} ({t.isoformat()})")
PY
)
# Last nightly step = last commit on hermes/loop. Git is the record, not the
# cron history (which lives inside the Hermes container and was misread).
LAST_STEP=$(git -C "$REPO" log -1 --date=format:'%Y-%m-%d %H:%M UTC' \
  --format='%cd %s' hermes/loop -- ops/loop/QUEUE.md 2>/dev/null)
[ -n "$LAST_STEP" ] || LAST_STEP="no hos-step commit yet"

esc() { printf '%s' "$1" | tr -d '"\\\n'; }
printf '{"wakeAgent": true, "context": {"date_jalali": "%s", "last_step": "%s", "disk_used": "%s", "memory": "%s", "load": "%s", "uptime": "%s", "public_ports": "%s", "next_queue_item": "%s"}}\n' \
  "$(esc "$JDATE")" "$(esc "$LAST_STEP")" "$(esc "$DISK")" "$(esc "$MEM")" "$(esc "$LOAD")" "$(esc "$UP")" "$(esc "$PUBLIC")" "$(esc "$NEXT")"
