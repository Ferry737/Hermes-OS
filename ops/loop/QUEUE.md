# LOOP QUEUE

The night job (`hos-step`) takes the first item marked `[ ]` that is not
`needs-ferry` or `needs-claude`, does it completely, and marks it `[x]` in the
same commit. One item per night. Nothing here trades, pays, emails, or opens a port.

Item states: `[ ]` todo · `[x]` done · `[!]` blocked (reason written under it).
Tags: `needs-ferry` = only Ferry can decide or do it. `needs-claude` = trading
math or architecture; the loop prepares inputs and stops.

Ferry or Claude may add items at the bottom. The loop may NOT add, delete, or
reword items; it may only change the box and write a `Result:` / `Blocked:` line.

---

- [x] **Q1. VPS inventory.** Write `ops/reports/vps-inventory.md`: OS and
  version, CPU cores, RAM, disk size and free space, swap, timezone
  (`timedatectl`), `hermes --version`, configured main model and cron model
  (`hermes config` output with keys redacted), installed: docker, python3, node,
  git, tailscale, opencode (version or "missing").
  *Never write:* IP addresses, hostnames, usernames, keys, tailnet names.
  *Done when:* the file exists, every line above is filled or says "missing",
  and `sh ops/gates/secrets.sh` exits 0.
  Result: ops/reports/vps-inventory.md written (Debian 13, 2-core EPYC, 7.8G RAM, 96G disk 25% used, no swap, UTC; hermes v0.21.5 docker, docker 26.1.5, python3 3.13.5, node v26.5.1, git 2.47.3; tailscale and opencode missing). secrets.sh: "secrets gate clean" exit 0; tests.sh exit 0.

- [ ] **Q2. Exposure audit (read-only).** Run `ss -tlnp` (or `ss -tln` without
  root). Write `ops/reports/exposure.md`: one row per listening port, the
  process, and whether it binds `127.0.0.1`/tailnet (OK) or `0.0.0.0`/`::`
  (PUBLIC). Do not change any firewall or service.
  *Done when:* the table exists. If any row is PUBLIC other than SSH, put
  "SECURITY: public port N" as the first line of tonight's report.

- [ ] **Q3. Backup check (read-only).** Find out whether `~/.hermes` and this
  repo are backed up anywhere (cron, systemd timers, restic/borg config).
  Write the answer into `ops/reports/backups.md`. Do not create a backup job.
  *Done when:* the file says "backed up by X" or "NOT backed up".

- [ ] **Q4. Free market data for the ORB test (T1).** Download BTCUSDT 1-minute
  klines for the last 12 full months from `https://data.binance.vision`
  (public, no key). Save under `~/hermes-data/binance/BTCUSDT/1m/` (outside this
  repo; never commit data). Verify each monthly zip against its `.CHECKSUM`
  file. Write `ops/reports/data-btcusdt.md` with month list, row counts, first
  and last timestamp, and any gaps over 5 minutes.
  *Done when:* 12 months downloaded, all checksums match, the report exists.

- [ ] **Q5. ORB backtest.** `needs-claude` — trading math. The loop does not
  write or run this. Claude writes it on top of Q4's data.

- [ ] **Q6. Plan cleanup A1–A4 in `ops/TASKS.md`.** Do A1, then A2, A3, A4 on
  later nights (each one counts as one item-night). Follow each task's own
  *Done when*.

- [ ] **Q7. Morning-report history.** Create `ops/reports/morning/` and make the
  morning job's output also land there as `YYYY-MM-DD.md` (copy from
  `~/.hermes/cron/output/`, newest file of job `hos-morning`). Do not commit
  anything that `secrets.sh` flags.
  *Done when:* yesterday's report is in the folder and committed.

- [ ] **Q8. Hardening proposal (draft only).** Using Q1–Q3, draft
  `ops/reports/hardening-proposal.md`: ufw rules, ssh settings, backup job.
  Applying any of it is `needs-ferry`; the loop applies nothing.
  *Done when:* the draft exists and lists each change with its rollback command.
