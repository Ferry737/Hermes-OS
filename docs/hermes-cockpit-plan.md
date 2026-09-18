# Hermes Cockpit — iPhone-first dashboard for Hermes Agent on a VPS

Status: plan, pre-implementation
Date: 2026-09-18
Decisions locked: D3 = theme + plugin on the built-in Hermes dashboard. D4 = PWA on the iPhone home screen. D2 = Tailscale private network, no public port.

---

## 1. Goal

One surface on my iPhone that shows what Hermes is doing on the VPS and lets me act on it, styled like the two Figma AI-OS dashboards (cockpit chrome, dense status HUD, dark palette), reachable only over my tailnet.

**Non-goals** (explicitly out of scope, do not let these creep in):

- Replacing the Hermes dashboard's Config / Keys / MCP / Profiles pages. They already work; they stay as-is.
- A native iOS app or App Store distribution.
- Exposing anything on the public internet.
- Rebuilding chat. Conversation stays in Telegram and the existing `/chat` tab.
- Multi-user, roles, or sharing. One user, one tailnet.

## 2. Ground truth (verified from the Hermes docs, 2026-09-18)

This is what already exists and must not be rebuilt:

| Capability | Where it lives | Source |
|---|---|---|
| Web dashboard, `hermes dashboard --port 9119 --host 127.0.0.1` | built in | docs/user-guide/features/web-dashboard |
| Status, Sessions, Logs, Analytics, Cron, Profiles, Skills, MCP, Config, Keys pages | built in | same |
| Live chat over `/api/pty` WebSocket (real TUI via xterm.js) | built in | same |
| Auth gate: non-loopback bind **fails closed** without a provider; basic auth via `HERMES_DASHBOARD_BASIC_AUTH_{USERNAME,PASSWORD,SECRET}` in `~/.hermes/.env` | built in | same |
| `GET /api/status` is **public** (pre-auth), reports `auth_required` + `auth_providers` | built in | same |
| Themes: YAML in `~/.hermes/dashboard-themes/`, 3-layer palette, typography + `fontUrl`, `layout.radius`/`density`, `layoutVariant: standard\|cockpit\|tiled`, `assets`, `componentStyles` (9 buckets), `colorOverrides`, `customCSS` (32 KiB cap) | built in | docs/user-guide/features/extending-the-dashboard |
| UI plugins: `~/.hermes/plugins/<name>/dashboard/{manifest.json,dist/index.js}`, IIFE bundle, SDK on `window.__HERMES_PLUGIN_SDK__`, React never bundled | built in | same |
| `tab.override` (replace a built-in route), `tab.hidden`, shell slots (`header-left`, `pre-main`, `overlay`, `sidebar`, …) and page-scoped slots (`sessions:top`, `cron:bottom`, …) | built in | same |
| Backend plugin routes: `dashboard/plugin_api.py` exposing a FastAPI `router`, mounted at `/api/plugins/<name>/`, behind the same auth gate, can `import` hermes internals (`SessionDB`, `load_config`) | built in | same |
| Prereqs: `uv pip install -e ".[web,pty]"` in `~/.hermes/hermes-agent`; Node for the TUI/frontend build | built in | same |

**What this means:** the deliverable is a theme file, one plugin directory, and a reverse-proxy/PWA wrapper. Not an application.

## 3. Architecture

### 3.1 Network path

```
  iPhone                          tailnet (WireGuard)                 VPS
 ┌────────────────┐                                        ┌──────────────────────────┐
 │ Safari / PWA   │                                        │ tailscaled               │
 │  home-screen   │── HTTPS (MagicDNS cert) ──────────────▶│  tailscale serve :443    │
 │  standalone    │    hermes.<tailnet>.ts.net             │        │ proxy           │
 └────────────────┘                                        │        ▼                 │
        ▲                                                  │  hermes dashboard        │
        │                                                  │  uvicorn 127.0.0.1:9119  │
        │                                                  │        │                 │
        │                                                  │        ├── SessionDB      │
        └──── no public port, no 0.0.0.0 bind ─────────────│        ├── config.yaml    │
                                                           │        └── cron / logs    │
                                                           └──────────────────────────┘
```

Nothing listens on a public interface. `ufw` keeps 9119 closed to the world; the only ingress is the tailnet.

### 3.2 Request path and the guard that will bite us

```
 PWA ──▶ tailscale serve (TLS terminate, sets Host: hermes.<tailnet>.ts.net)
      ──▶ 127.0.0.1:9119
             ├─ peer-IP guard      : peer is loopback (the proxy)  → passes
             ├─ DNS-rebinding guard: Host must match the bind host → RISK
             └─ auth gate          : engages on NON-loopback bind  → RISK
```

Two documented guards interact badly with a TLS-terminating proxy:

1. **Auth may not engage.** The docs state the gate engages when the dashboard is bound to a non-loopback address; a loopback bind reports `auth_required: false`. Behind `tailscale serve` the bind *is* loopback, so the dashboard may serve every tailnet device with no login at all.
2. **Host-header guard.** If we instead bind to the tailscale IP to force the gate on, the proxy's `Host:` is the MagicDNS name, not the IP, and the rebinding guard can reject the WebSocket with close code **4403**.

**Phase 0 must settle this empirically before anything else is built.** Probe:

```bash
# on the VPS
curl -s http://127.0.0.1:9119/api/status | jq '.auth_required, .auth_providers'
# from the iPhone/laptop over the tailnet
curl -s https://hermes.<tailnet>.ts.net/api/status | jq '.auth_required, .auth_providers'
```

Decision table from the result:

| `auth_required` over the tailnet | Action |
|---|---|
| `true` + `["basic"]` | done, keep loopback bind + `tailscale serve` |
| `false` | bind `--host <tailscale-ip>` instead and re-test; if WS then closes 4403, put Caddy on the tailscale IP with `header_up Host {upstream_hostport}` and keep the dashboard on loopback |

Tailnet ACLs are a second layer, not a substitute: `tailscale serve` + a device-scoped ACL limits which of my devices can reach :443 at all.

### 3.3 Composition on the page

```
┌─ Hermes dashboard shell (owned by Hermes, never forked) ──────────┐
│ header-left ◀── plugin slot: crest                                │
│ ┌───────────────────────────────────────────────────────────────┐ │
│ │ pre-main  ◀── plugin slot: HUD strip (agent, gateway, budget) │ │
│ ├───────────────────────────────────────────────────────────────┤ │
│ │ route "/"  ◀── plugin tab.override: Cockpit home              │ │
│ │   • live status      • active sessions   • next cron runs     │ │
│ │   • 7-day token/cost • quick actions                          │ │
│ ├───────────────────────────────────────────────────────────────┤ │
│ │ /sessions /logs /cron /analytics /config /env … unchanged     │ │
│ └───────────────────────────────────────────────────────────────┘ │
│ overlay   ◀── plugin slot: vignette + grain (reduced-motion safe) │
└───────────────────────────────────────────────────────────────────┘
        ▲ palette, typography, radius, density, componentStyles
        └── theme YAML (hermes-cockpit.yaml)
```

**Layout variant decision: `standard`, not `cockpit`.** `cockpit` adds a fixed 260px sidebar rail. On a 390px iPhone that is two thirds of the viewport for chrome. The AI-OS look comes from the palette, clip-path card chrome, and typography, not from the rail. The HUD goes in `pre-main`, which renders in every layout variant. If a desktop rail is wanted later, it is one `layoutVariant` line plus a `sidebar` slot registration, additive.

### 3.4 Data flow — one request, not five

The built-in Status page polls every 5s. A naive override would fire `/api/status`, `/api/sessions`, `/api/cron`, `/api/analytics` separately — four round trips per tick over cellular.

```
 Cockpit home ──(1 req / 5s)──▶ GET /api/plugins/hermes-cockpit/summary
                                     │
                                     ├─ status      (in-process)
                                     ├─ SessionDB.list_sessions(limit=20)
                                     ├─ cron next-runs
                                     └─ 7-day token/cost rollup
                                     ▼
                                 { agent, gateway, sessions[], cron[], usage{} }
                                 server-side cache, TTL 4s, single-flight
```

Poll pauses on `document.visibilityState === "hidden"` and resumes on focus. On a phone this is the difference between a dashboard you leave open and one that eats the battery.

## 4. Work breakdown

**Phase 0 — prove the path (blocking, ~30 min)**
- 0.1 `uv pip install -e ".[web,pty]"`, confirm `hermes dashboard` starts.
- 0.2 Set `HERMES_DASHBOARD_BASIC_AUTH_{USERNAME,PASSWORD,SECRET}` (`openssl rand -base64 32`).
- 0.3 `tailscale serve --bg https / http://127.0.0.1:9119`; probe `/api/status` per §3.2; record which branch of the decision table applies.
- 0.4 Open the dashboard in iPhone Safari over the tailnet. Screenshot every built-in page at 390px. This is the baseline the theme has to improve on, and it tells us which pages are already usable and which need page-scoped slot fixes.
- 0.5 Probe whether a non-TUI prompt path exists (`API_SERVER_ENABLED` appears in the dashboard's Keys page): `hermes --help`, `grep -r API_SERVER_ENABLED ~/.hermes/hermes-agent`. Result decides whether "send a prompt" is a real quick action or a link to Telegram.

**Phase 1 — theme (~1h)**
- 1.1 `~/.hermes/dashboard-themes/hermes-cockpit.yaml`: 3-layer palette, `fontUrl` for display + mono faces, `radius: 0.25rem`, `density: compact`, `layoutVariant: standard`.
- 1.2 `componentStyles`: `card` clip-path corner cuts + inset hairline, `header` gradient, `badge`, `progress`.
- 1.3 `customCSS`: phone media queries, `@media (prefers-reduced-motion: reduce)` kill-switch for grain/scan effects, safe-area insets (`env(safe-area-inset-*)`) so the PWA does not sit under the notch or home indicator.
- 1.4 Verify every built-in page still reads correctly under the new palette — contrast check on Sessions, Logs (severity colors), Analytics (chart series).

**Phase 2 — plugin backend (~1h)**
- 2.1 `dashboard/plugin_api.py`: `GET /summary` (aggregate + 4s cache + single-flight), `GET /manifest.webmanifest`, `GET /icons/{size}.png`.
- 2.2 Error contract: DB unavailable → `503` with `{"error": "..."}`, never a traceback; partial failure (cron readable, analytics not) returns the partial payload with a `degraded: ["usage"]` list so the UI can grey one card instead of blanking the page.
- 2.3 Guard the manifest route: it must be reachable by the same auth session Safari holds at install time.

**Phase 3 — plugin UI (~2h)**
- 3.1 `manifest.json`: `tab.override: "/"`, `icon: "Activity"`, `css: "dist/style.css"`, `api: "plugin_api.py"`.
- 3.2 `dist/index.js` (IIFE, React from the SDK, no bundler required): Cockpit home + `pre-main` HUD + `header-left` crest + `overlay` chrome.
- 3.3 Keep pure logic (formatting, rollups, status derivation) in exported-testable functions separate from render.
- 3.4 Touch targets ≥44px, one-column under 480px, no hover-only affordances.

**Phase 4 — PWA (~1h)**
- 4.1 Inject `<link rel="manifest">`, `apple-mobile-web-app-capable`, `apple-mobile-web-app-status-bar-style`, `apple-touch-icon` from the plugin bundle on mount.
- 4.2 `display: standalone`, `theme_color`, `background_color`, portrait-primary, 180/192/512 icons.
- 4.3 Add to Home Screen, verify standalone launch, safe areas, and that the separate cookie jar login works once and sticks.
- 4.4 Service worker + Web Push: **deferred**, only if lock-screen alerts are wanted. Documented as the next increment, not built now.

**Phase 5 — service + hardening (~45 min)**
- 5.1 `hermes-dashboard.service` (systemd, `Restart=always`, `EnvironmentFile=%h/.hermes/.env`), enabled at boot, independent of the gateway unit.
- 5.2 `ufw`: deny 9119 from everything except the tailnet interface.
- 5.3 Log rotation check; confirm the dashboard survives a reboot and a `hermes` upgrade.

## 5. Edge cases (each one gets a test)

| # | Case | Expected behavior |
|---|---|---|
| 1 | Phone off the tailnet | Clear "not connected to tailnet" state, not a spinner forever |
| 2 | Gateway stopped, dashboard up | Cockpit shows gateway `stopped` in red, other cards still render |
| 3 | Zero sessions, zero cron jobs | Empty states with one action each, never `NaN` / `undefined` |
| 4 | Session DB locked mid-read | `503` + degraded card, poll backs off to 15s, recovers on its own |
| 5 | Phone sleeps / tab hidden 8h | Poll suspended; on focus, one immediate fetch, no 5760 queued requests |
| 6 | Hermes upgraded, SDK changed | Plugin fails to register → dashboard still boots; smoke script catches it |
| 7 | `prefers-reduced-motion` | No grain, no scanlines, no animated counters |
| 8 | Landscape / iPad width | Layout reflows, HUD goes multi-column, nothing clipped |
| 9 | Auth session expired in the PWA | Redirect to login inside the standalone window, return to `/` after |
| 10 | Very long session titles / RTL text | Truncation with ellipsis, no horizontal page scroll |
| 11 | Clock skew on "next cron run" | Render server-provided relative strings, not client-computed |
| 12 | Two devices open at once | Both poll independently; no shared state assumptions |

## 6. Test plan

**Backend (pytest, in the plugin directory):**
- `/summary` shape contract, including every key present under empty data.
- Cache TTL: two calls inside 4s hit the DB once (assert with a spy).
- Single-flight: 10 concurrent calls → one DB read.
- Unauthenticated request → 401 before the handler runs.
- DB error → 503 with JSON body, no traceback leak.
- Partial failure → `degraded` list populated, HTTP 200.

**Frontend (vitest on the pure functions):**
- Status derivation (`running`/`stopped`/`degraded`) from every status payload permutation.
- Token/cost rollup math against a fixture, including a day with zero sessions.
- Relative-time formatting at boundaries (59s, 60s, 24h, 7d).

**Integration (shell, `scripts/smoke.sh`, run after every Hermes upgrade):**
- `/api/status` reachable over the tailnet and `auth_required == true`.
- Theme file parses and appears in the theme list.
- Plugin registered: `/api/plugins/hermes-cockpit/summary` returns 200 authenticated, 401 unauthenticated.
- Manifest route returns `application/manifest+json`.

**Device matrix (manual, once per phase, screenshots archived):**
- iPhone Safari tab and installed PWA, portrait + landscape, 390px and 430px.
- Light and dark, default and largest Dynamic Type.
- Network Link Conditioner on 3G: first paint and poll behavior.

**Regression:** the `hermes` upgrade smoke test is the one test that will actually save the project. Plugin SDKs this young move.

## 7. Rollout and rollback

Every artifact is drop-in. Rollback is ten seconds and needs no build:

```bash
mv ~/.hermes/plugins/hermes-cockpit ~/.hermes/plugins/.off-hermes-cockpit
hermes config set dashboard.theme default   # or pick another theme in the header
# refresh the browser
```

Roll forward the same way. No migration, no data touched, nothing to un-deploy.

## 8. Risks, ranked

1. **Auth gate does not engage behind the loopback bind** (§3.2). An unauthenticated agent-control panel, even on a tailnet, is the one thing here that can actually hurt. Phase 0.3 settles it; if it cannot be settled, the build does not proceed past Phase 0.
2. **Plugin SDK churn between Hermes releases.** Mitigation: pin the Hermes version in the plan notes, run `scripts/smoke.sh` after every upgrade, keep the plugin small enough to fix in one sitting.
3. **iOS PWA cookie jar is separate from Safari.** One extra login inside the installed app. Documented, not fixable from our side.
4. **xterm.js chat on a 390px screen with a software keyboard.** Not solved by this plan. Conversation belongs in Telegram; the dashboard is observability plus control.
5. **Theme is global.** Desktop and phone share one theme; anything phone-specific lives in media queries inside `customCSS` (32 KiB cap — watch it).
6. **`/api/status` is public pre-auth.** Acceptable on a tailnet, fatal on a public bind. The `ufw` rule and the "never `--host 0.0.0.0` on a public NIC" note are part of the deliverable, not advice.

## 9. Open questions

- Q1: Does a non-TUI prompt endpoint exist (`API_SERVER_ENABLED`)? Phase 0.5 answers it. If yes, "send a prompt" becomes a first-class quick action on the cockpit home.
- Q2: The two Figma community files could not be read without a login. The theme's palette and chrome are derived from the AI-OS cockpit language described in the brief; share two screenshots and the theme is a 15-minute revision.

## 10. File inventory

```
~/.hermes/dashboard-themes/hermes-cockpit.yaml          # theme
~/.hermes/plugins/hermes-cockpit/dashboard/
  manifest.json                                         # tab override, slots, api
  dist/index.js                                         # IIFE bundle (no build step)
  dist/style.css                                        # plugin-scoped CSS, theme vars only
  plugin_api.py                                         # /summary, /manifest.webmanifest, /icons
  assets/icon-{180,192,512}.png
  tests/test_plugin_api.py
  tests/summary.test.js
/etc/systemd/system/hermes-dashboard.service
scripts/smoke.sh
```

Six source files, no new service, no new auth system, no fork.
