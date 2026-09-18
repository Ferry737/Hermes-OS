# TASKS

Worked top to bottom. One task per turn. Check a box only when its **Done when**
line is literally true — a command you ran and whose output you can quote.

Never skip ahead. If a task is blocked, write why under it, leave it unchecked,
and move to the next task that is not blocked by it.

---

## A. Finish the plan document

- [ ] **A1.** Fold the nine approved remedies (README table) into the body of
  `docs/hermes-cockpit-plan.md`, each in the section it belongs to, not as an appendix.
  *Done when:* every one of the nine appears in its phase or risk section, and the
  README table's "still need folding in" sentence is deleted.
- [ ] **A2.** Add a "NOT in scope" section listing deferred work with one line of
  rationale each (service worker and Web Push, desktop cockpit rail, multi-user, chat replacement).
  *Done when:* the section exists and names at least those four.
- [ ] **A3.** Add a "What already exists" section: which Hermes capability covers which
  need, and whether this plan reuses or rebuilds it.
  *Done when:* every row in the §2 ground-truth table is marked reuse or rebuild.
- [ ] **A4.** Add the implementation task list with priorities and verification commands.
  *Done when:* every task carries a P1/P2/P3 and a command that proves it.

## B. Phase 0 — prove the path (blocking; nothing below starts until B is done)

- [ ] **B1.** Install the dashboard extras: `uv pip install -e ".[web,pty]"` in
  `~/.hermes/hermes-agent`, confirm `hermes dashboard` starts.
  *Done when:* `curl -fsS http://127.0.0.1:9119/api/status` returns JSON.
- [ ] **B2.** Set `HERMES_DASHBOARD_BASIC_AUTH_{USERNAME,PASSWORD,SECRET}` in
  `~/.hermes/.env` (secret from `openssl rand -base64 32`). Never echo the values into
  chat, a file in this repo, or a commit message.
  *Done when:* the three keys exist in `~/.hermes/.env`.
- [ ] **B3.** Expose over the tailnet: `tailscale serve --bg https / http://127.0.0.1:9119`.
  *Done when:* the dashboard loads over the tailnet hostname from another device.
- [ ] **B4.** **Resolve the auth-gate question** (review finding #1). Probe
  `auth_required` and `auth_providers` both locally and over the tailnet, then follow the
  decision table in plan §3.2. Record which branch applied and the evidence.
  *Done when:* `/api/status` over the tailnet reports `auth_required: true` with
  `basic` in providers, and the result is written into the plan.
- [ ] **B5.** Write the tailnet ACL so only your own devices reach port 443 on this host,
  and verify from a device that is not on the allow list.
  *Done when:* an allowed device loads the dashboard and a non-allowed one times out.
  Both results recorded.
- [ ] **B6.** `echo 1 > ops/.phase`.
- [ ] **B7.** Answer the open question: does a non-TUI prompt endpoint exist?
  Check `hermes --help` and `grep -r API_SERVER_ENABLED ~/.hermes/hermes-agent`.
  *Done when:* the answer is written into plan §9 as yes-with-endpoint or no.

## C. Phase 1 — theme

- [ ] **C1.** `theme/hermes-cockpit.yaml`: palette, typography with `fontUrl`,
  `radius: 0.25rem`, `density: compact`, `layoutVariant: standard`.
  *Done when:* the file parses and appears in the dashboard's theme picker.
- [ ] **C2.** `componentStyles` for card, header, badge, progress.
- [ ] **C3.** `customCSS`: phone media queries, `prefers-reduced-motion` kill switch,
  `env(safe-area-inset-*)` padding. Honour the CSS ownership rule (remedy #6): only
  tokens and chrome that must reach built-in pages live here.
  *Done when:* under 32 KiB and every built-in page still readable.
- [ ] **C4.** Contrast check Sessions, Logs severity colours, and Analytics series
  under the new palette.

## D. Phase 2 — plugin backend

- [ ] **D1.** `plugin/dashboard/adapters.py` (remedy #3): the only file importing Hermes
  internals, with a header naming what breaks on upgrade.
- [ ] **D2.** `plugin/dashboard/tests/test_adapters.py`: contract test that fails loudly
  and names the symbol when an internal moves.
- [ ] **D3.** `plugin/dashboard/plugin_api.py`: `GET /summary` with tiered cache TTLs
  (remedy #9: status 4s, sessions 15s, cron 60s, usage 5min) and single-flight.
- [ ] **D4.** Payload shaped to the thin home (remedy #8): 5 sessions, no conversation
  previews, plus a test asserting the response stays under 8 KiB.
- [ ] **D5.** Error contract: DB down → 503 JSON not a traceback; partial failure → 200
  with `degraded: [...]`.
- [ ] **D6.** `GET /manifest.webmanifest` and `GET /icons/{size}`.
- [ ] **D7.** Tests for every branch in D3–D6 including the 401 path.

## E. Phase 3 — plugin UI

- [ ] **E1.** `plugin/dashboard/manifest.json`: `tab.override: "/"`, icon, css, api.
- [ ] **E2.** `plugin/dashboard/dist/index.js` as a plain IIFE. React from
  `window.__HERMES_PLUGIN_SDK__`, never bundled.
- [ ] **E3.** Thin cockpit home (remedy #5): HUD and quick actions, links out to the
  built-in Sessions / Logs / Cron / Analytics pages. Do not re-implement them.
- [ ] **E4.** Three distinct failure states (remedy #2): tailnet unreachable, service
  down, 5xx — each with its own message and its own next action.
- [ ] **E5.** Pure functions (`deriveAgentState`, `rollupUsage`, `relTime`,
  `pollController`) kept separate from render, with vitest coverage including the
  boundary cases in the plan's test section.
- [ ] **E6.** Poll pauses on `visibilitychange`, one immediate fetch on focus.
- [ ] **E7.** Touch targets ≥44px, single column under 480px.
- [ ] **E8.** `echo 3 > ops/.phase` once deployed and loading.

## F. Phase 4 — PWA

- [ ] **F1.** Inject manifest link and the Apple meta tags on mount.
- [ ] **F2.** Icons at 180/192/512.
- [ ] **F3.** Manual device check: add to home screen, launch standalone, confirm safe
  areas and that the separate cookie jar login sticks.
  *Done when:* the checklist in `ops/DEVICE-CHECKS.md` is filled in with real results.

## G. Phase 5 — service, deploy, hardening

- [ ] **G1.** `ops/hermes-dashboard.service` with `Restart=always`, `RestartSec=5`,
  `StartLimitIntervalSec=60`, `StartLimitBurst=5` (remedy #2). Enabled at boot.
- [ ] **G2.** `ufw` denies 9119 from everything except the tailnet interface.
- [ ] **G3.** `Makefile` with `deploy` (rsync into `~/.hermes/`) and `smoke` (remedy #4).
- [ ] **G4.** Playwright covering the four forceable error states (remedy #7):
  offline, 502, degraded, 401.
- [ ] **G5.** `ops/DEVICE-CHECKS.md` for the iOS-only manual checks.
- [ ] **G6.** Reboot the VPS and confirm everything comes back without hands.

## H. Close out

- [ ] **H1.** `make smoke` green from a cold start.
- [ ] **H2.** README updated: what exists, how to deploy, how to roll back.
- [ ] **H3.** Rollback rehearsal: disable the plugin, switch theme to default, confirm the
  dashboard is untouched, restore. Record that it worked.
- [ ] **H4.** Final commit and push.
