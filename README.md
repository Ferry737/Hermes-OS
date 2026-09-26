# hermes-cockpit

Two deliverables from one working session (2026-09-18).

## `docs/hermes-cockpit-plan.md`

Engineering plan for an iPhone-first dashboard onto **Hermes Agent** running on a VPS,
reachable only over a Tailscale tailnet, installed as a PWA on the home screen.

The load-bearing finding: Hermes already ships a web dashboard (`hermes dashboard`) with a
documented three-layer extension system — theme YAML, UI plugin, and a FastAPI backend route.
So this is a theme file plus one plugin directory, not a second application. Sessions, cron,
logs, analytics, memory, skills and live chat already exist and are not rebuilt.

The plan covers the network path, the auth-gate guards that interact badly with a
TLS-terminating proxy, a single aggregated `/summary` endpoint, twelve edge cases, a test plan,
and ten-second rollback.

**Status: reviewed, not yet implemented.** It went through a four-section engineering review
(architecture, code quality, tests, performance). Nine findings were raised and each remedy was
approved:

| # | Finding | Approved remedy |
|---|---------|-----------------|
| 1 | Tailnet ACL named in prose but never built or tested | ACL becomes a Phase 0 deliverable with a verification test |
| 2 | `Restart=always` with no backoff; no UI state for "service down" | systemd backoff + three distinct failure states |
| 3 | Direct imports of unversioned Hermes internals | isolate behind `adapters.py` + a contract test |
| 4 | No answer for how files reach the VPS | git repo + `make deploy` (this repo is step one) |
| 5 | `tab.override` on `/` re-implements the built-in Status page | keep the home thin: HUD + navigation |
| 6 | CSS could live in two places with no rule | theme = tokens and global chrome, plugin = its own components |
| 7 | 0 of 14 user flows covered | Playwright for forceable error states + manual iOS checklist |
| 8 | 5s polling shipping data the page no longer renders | payload trimmed to the page + a size-ceiling test |
| 9 | One 4s cache TTL across four sources | tiered TTLs per source |

Not yet folded into the plan body: those nine remedies, the "NOT in scope" and
"what already exists" sections, the implementation task list, and the review report.

Known gaps: no outside-model review was run (Codex is not installed locally), and the two
Figma references behind the visual direction could not be read without a login.

## `design/claude-os-academic.html`

A Persian (RTL) guide page — a daily operating system for running three roles with Claude:
fintech founder, independent quant, DeFi investor. Rebuilt from an earlier version into an
academic, Figma-style layout: sections rendered as canvas frames with live dimension read-outs,
a layers rail with scroll-spy, tabbed roles, copyable prompt blocks, light and dark themes.

Self-contained, no build step, no network dependency except the webfont. Opens from `file://`
(the clipboard path has a fallback for exactly that reason). Text heights are measured with
Pretext, inlined into the page and applied as `min-height` so a mis-measure can never clip
Persian text.

`claude-os-academic.src.html` is the pre-inline source; the `.html` next to it is what ships.

Design checks: `impeccable 0.1.3` reports `slop=0 quality=0`, with one advisory for the
intentional canvas grid. Verified at 375 / 768 / 1440 px plus dark mode.

## `profile.md`

Implementation-ready specification for the **Hermes Research Engine** (HRE): a separate,
self-hosted multi-agent system (Researcher, Evaluator, Scorer, Reporter, orchestrated by a
non-LLM Conductor over a Postgres task queue) that researches fintech markets and ranks
startup concepts against an evidence-backed unicorn rubric. It covers the agent architecture,
the scoring rubric and calibration approach, the Ubuntu + Docker + Postgres + Caddy +
Prometheus/Grafana/Loki stack with hardening, step-by-step deployment, and the 24/7 runbook.

HRE coexists with Hermes Agent on the same VPS without touching `~/.hermes`: it lives in
`/opt/hermes-research`, is served on tailnet port 8443 (443 stays with the cockpit), and keeps
its own secrets. **Status: specification, not yet implemented.**
