# Backup check (Q3)

Read-only audit, run 2026-10-15 ~01:00 UTC on branch `hermes/loop`.
Nothing was created, installed, scheduled, or changed.

## Verdict

| What | Backed up? |
| --- | --- |
| This repo (`/opt/data/hermes-os`) | **Backed up by git → GitHub remote `origin`.** `git ls-remote origin refs/heads/hermes/loop` returns `cf345bf…`, identical to local `HEAD`. |
| Hermes home (`HERMES_HOME=/opt/data`: `config.yaml`, `.env`, `state.db`, `sessions/`, `memories/`, `skills/`, `cron/`) | **NOT backed up** — no backup tool, no scheduler, no off-host copy. |

Hermes home is ~1.2 G on this host and includes every credential file
(`.env`, `auth.json`, `.git-credentials`). It exists on one disk only.

## What was checked, and what was found

**Schedulers — none that backs anything up.**

- `crontab` binary: **not installed**. `/var/spool/cron/` and
  `/var/spool/cron/crontabs/`: **do not exist**.
- `/etc/crontab`: absent. `/etc/cron.d/` and `/etc/cron.hourly/`:
  **absent**. `/etc/cron.daily/` holds only `apt-compat` and `dpkg`
  (package lists, not our data).
- `systemctl`: **not installed** → no systemd timers, and no user units
  (`~/.config/systemd/user/` absent). `anacron` config absent.
- Hermes' own scheduler (`hermes cron list`) has four jobs, none of them a
  backup: `hos-morning` (30 5 * * *, active), `hos-step` (0 1 * * *, active),
  `jarvis-bridge-watchdog` (every 15m, paused), `upwork-model-job-watch`
  (every 360m, paused).

**Backup tools — none installed.**

`restic`, `borg`, `borgmatic`, `resticprofile`, `kopia`, `bupstash`,
`duplicity`, `rsnapshot`, `rclone`, and `rsync` were each checked in
`/usr/bin` and `/usr/local/bin`: all **missing**. No restic/borg/rclone
config directory exists anywhere under the home directory.

Hermes does ship a backup command (`hermes backup`, "Create a zip archive of
your entire Hermes configuration, skills, sessions, and data"), but
**no `hermes-backup-*.zip` exists anywhere on the host** and nothing
schedules it. It has never been run here.

**Local-only copies that exist (same disk, not a backup):**

| Path | Contents | Covers |
| --- | --- | --- |
| `/opt/data/backups/config/` | 5 × `config.yaml.good.*` snapshots (2026-10-13 → 2026-10-14, 2.1–3.2 K) + 1 `config.yaml.pre-docker-migrate.*` | config only |
| `/opt/data/backups/config/.env.pre-docker-migrate.*` | 1 file, 26 K, 2026-10-08 | `.env`, one point in time |
| `/opt/data/.env.bak`, `/opt/data/.env.bak2` | manual `.env` copies, 2026-10-10 | `.env` only |
| `/opt/data/.curator_backups/blobs/` | 88 blobs, 660 K total, skill markdown (SKILL.md content confirmed by reading one), newest 2026-10-14 | skill files only |
| `/opt/data/home/.claude/backups/` | 2 × `.claude.json.backup.*`, 2026-10-08 | one Claude Code settings file |

All of these are on the same overlay filesystem as the originals. A disk
failure, container rebuild, or `rm -rf` takes them with the data.

## Notes

- The repo's `.gitignore` is `*.log` / `.DS_Store` only. Market data is
  instructed to live outside the repo (`~/hermes-data/…`, Q4), so nothing
  large is at risk of being committed — but any large directory placed inside
  the repo later would be tracked.
- Two of the local copies (`/opt/data/.env.bak`, `.env.bak2`,
  `.env.pre-docker-migrate.*`) hold live credentials. They are untracked and
  must stay untracked; `secrets.sh` would flag them if they were added.

## needs-ferry

A real backup of the Hermes home is a `needs-ferry` decision: it costs money
(off-host storage), and encrypting a directory full of keys is exactly the
kind of irreversible setup the loop must not start on its own. Draft options
belong to Q8.
