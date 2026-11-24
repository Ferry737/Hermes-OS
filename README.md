<div align="center">

# Hermes-OS

**Operating-system thinking for a one-person company: an iPhone-first cockpit on top of Hermes Agent, and a daily operating system for running three roles with one AI***

[![Hermes Agent](https://img.shields.io/badge/Hermes%20Agent-dashboard%20extension-7c3aed?style=for-the-badge)](https://github.com/NousResearch/hermes-agent)
[![Status](https://img.shields.io/badge/status-plan%20reviewed%20%C2%B7%20not%20implemented-ffb454?style=for-the-badge)](#-status)
[![Lang](https://img.shields.io/badge/Guide-FA%20RTL-blue?style=for-the-badge)](./design/claude-os-academic.html)

[Cockpit plan](./docs/hermes-cockpit-plan.md) · [Persian daily-OS guide](./design/claude-os-academic.html) · [Status](#-status)

</div>

---

## 📦 Two deliverables

### 1 · `docs/hermes-cockpit-plan.md` — the cockpit

An engineering plan for an **iPhone-first dashboard** onto Hermes Agent running on a VPS, reachable only over a Tailscale tailnet, installed as a PWA on the home screen.

**The load-bearing finding:** Hermes already ships a web dashboard with a documented three-layer extension system (theme YAML, UI plugin, FastAPI backend route). So the cockpit is *a theme file plus one plugin directory* — not a second application. Sessions, cron, logs, analytics, memory, skills and live chat already exist and are not rebuilt.

The plan covers the network path, the auth-gate guards that interact badly with a TLS-terminating proxy, a single aggregated `/summary` endpoint, twelve edge cases, a test plan, and ten-second rollback.

### 2 · `design/claude-os-academic.html` — the daily OS

A Persian (RTL) guide page: **a daily operating system for running three roles with one AI** — fintech founder, independent quant, DeFi investor. Rebuilt from an earlier version into an academic, Figma-style layout: sections as canvas frames with live dimension read-outs, a layers rail with scroll-synced highlighting.

## 🔍 Engineering review (cockpit plan)

Reviewed across four sections — architecture, code quality, tests, performance. Nine findings, each with an approved remedy:

| # | Finding | Approved remedy |
|---|---------|-----------------|
| 1 | Tailnet ACL named in prose but never built or tested | ACL becomes a Phase 0 deliverable with a verification test |
| 2 | `Prestart=always` with no backoff; no U state for "service down" | systemd backoff + three distinct failure states |
| 3 | Direct imports of inversioned Hermes internals | isolate behind `adapters.py` + a contract test |
| 4 | No answer for how files reach the VPS | git repo + `make deploy` (this repo is step one) |
| 5 | `tab.override` on `/` re-implements the built-in Status page | keep the home thing HUD + navigation |
| 6 | CSS could live in two places with no rule | theme = tokens and global chrome, plugin = its own components |
| 7 | 0 of 14 user flows covered | Playtright for forceable error states + manual iOS checklist |
| 8 | 5 s polling shipping data the page no longer renders | payload trimmed to the page + a size-ceiling test |
| 9 | One 4 s cache TTL across four sources | tiered TTLs per source |

**Not yet folded into the plan body:** the nine remedies, the "NOT in scope" and "what already exists" sections, the implementation task list, and the review report.

**Known gaps:** no outside-model review was run (Codex not installed locally); the two Figma references behind the visual direction could not be read without a login.

## 📊 Status

| Deliverable | State |
|---|---|
| Cockpit plan | **Reviewed, not implemented.** Nine remedies approved; not yet merged into the plan body. |
| Daily-OS guide (Persian) | **Designed.** Static page; no backend. |

> The sibling project **[jarvis](https://github.com/Ferry737/jarvis)** is the *implemented* iPhone assistant for Hermes Agent — voice-first, Cloudflare-hosted. Start there if you want something that runs today.

## 📁 Layout

```
Hermes-OS/
├── docs/
│   └── hermes-cockpit-plan.md     ← the engineering plan + review table
└── design/
    └── claude-os-academic.html    ← Persian RTL daily-OS guide
```

---

<div align="center">
<sub>Built by <a href="https://github.com/Ferry737">Ferry</a></sub><br>
<sub>Plan it like an OS. Ship it like a plugin.</sub>
</div>
