# Orchestra — your 24/7 command surface for Hermes Agent

Status: specification, not yet built. Date: 2026-09-26.
Read together with `orchestra/PLAYBOOK.md` (how to work) and `orchestra/ops/TASKS.md` (what to do next).

---

## 1. What it is, in one paragraph

Orchestra is a private web app you open on your phone or laptop to give orders to your Hermes Agent and see them done. Inside the system, **Hermes Agent is the CEO**: it owns memory, skills and cron, decides how to work, and delegates to the models and sub-agents connected to it. **Orchestra is your personal assistant at the front desk.** It takes your instruction instantly, hands it to the CEO, streams the answer back as it is written, keeps a board of the long jobs it has running for you, and is available 24/7. Orchestra never talks to a model directly; every request goes through Hermes, so Hermes stays the single brain, the single budget and the single audit trail.

```
You ──▶ Orchestra (PA: fast, always on, remembers your task list)
            │  one HTTPS request over your tailnet, API key held server-side
            ▼
        Hermes Agent gateway API (CEO: memory, skills, cron, delegation)
            │
            ▼
        Models and sub-agents connected to Hermes (staff)
```

## 2. What "faster than Telegram" can and cannot mean

Be exact about this, because it is the headline promise.

Orchestra **cannot** make a model think faster. The time a model takes to produce its answer is the same whether you ask from Telegram or from Orchestra.

Orchestra **can** win in four measurable ways:

1. **Streaming.** You see the first words as soon as the model produces them, instead of waiting for the whole reply to arrive as one Telegram message.
2. **Fewer hops.** Browser → your server over the tailnet, instead of phone → Telegram's servers → bot polling → your server and back.
3. **Background jobs.** Long instructions run as tasks. You don't wait at all; you come back to a finished result on the task board.
4. **Model choice per request**, only if Phase 0 proves the gateway API honours a per-request `model` parameter. Quick questions can then go to the fastest connected model.

Targets, measured by `orchestra/bench/bench.py` (task P6):

| Metric | Target |
|---|---|
| Orchestra overhead vs calling the gateway directly (time to first token) | ≤ 100 ms at p50 |
| Time until you see the first words | ≤ gateway time-to-first-token + 100 ms |
| Page load on the phone (app shell, warm) | ≤ 1 s |
| Background task survives closing the page | yes, always |

The Telegram baseline is measured by you, with a stopwatch, on the same three benchmark prompts (task P6.3). Nobody may claim "faster" without both numbers written into `orchestra/docs/BENCH.md`.

## 3. Settled decisions

These are fixed so that any model working this loop produces the same system. A model that thinks one is wrong writes its case in `orchestra/docs/PROPOSALS.md` and keeps building to the spec. Changing a settled decision is the owner's call.

| ID | Decision | Why |
|---|---|---|
| D1 | Orchestra talks only to the Hermes gateway API at `127.0.0.1:8642`, authenticated with `API_SERVER_KEY`. | Verified live on 2026-09-25: `GET /v1/models` with `Authorization: Bearer <key>` returned 200. Hermes stays the CEO. |
| D2 | Backend: Python 3, FastAPI + uvicorn + httpx, in its own venv at `/opt/data/orchestra/.venv`. | Python is already in the container; a small typed async server with streaming support. |
| D3 | Frontend: plain HTML, CSS and ES-module JavaScript, served by the backend. **No build step, no npm, no framework.** | No Node dependency on the server, and no bundler that could compile a secret into public JavaScript (the Vite `VITE_*` failure mode). |
| D4 | The API key is read by the backend from `/opt/data/.env` at startup and **never** reaches the browser, a log line, or the repo. | Lesson from the 2026-09-24 incident. |
| D5 | Bind `127.0.0.1:8790` only. Reach it through `tailscale serve --bg --https=8443 http://127.0.0.1:8790`. | Tailnet-only, HTTPS (needed for the PWA and service worker), no public port. |
| D6 | **No public exposure, ever.** No cloudflared, ngrok, localtunnel or Tailscale Funnel. | Lesson from the 2026-09-24 incident. Enforced by `orchestra/ops/gates/exposure.sh`. |
| D7 | Identity: the backend accepts a request only if the `Tailscale-User-Login` header (set by `tailscale serve`) matches `ORCHESTRA_OWNER_LOGIN`. Fallback, if Phase 0 or P5 shows the header is absent: a passcode session cookie. | Uses tailnet identity; no password to leak. |
| D8 | State in SQLite at `/opt/data/orchestra/data/orchestra.db`: conversations, messages, tasks, latency samples. | One file, on the persistent volume, trivially backed up. |
| D9 | Runtime lives on the persistent volume: code deployed to `/opt/data/orchestra/app`, kept alive by `/opt/data/services_keepalive.sh` (the existing Hermes cron job, every 5 minutes, real HTTP check). | The container is rebuilt without warning; only `/opt/data` and the Hermes cron survive. |
| D10 | The service worker caches the app shell only. It never caches `/api/*` responses. | A cached API answer is a stale or leaked answer. |

## 4. What exists already (do not rebuild)

- **Hermes gateway API** on `127.0.0.1:8642` (Bearer auth). Endpoint surface beyond `/v1/models` is **unverified**; Phase 0 establishes it.
- **Hermes dashboard** (status, sessions, logs, cron, live chat). Orchestra links to it; it does not copy it.
- **Hermes Cockpit plan** (`docs/hermes-cockpit-plan.md`): the status HUD. Orchestra is the command surface. They share the network and auth decisions and may merge later; not in v1.
- **JARVIS app** at `/opt/data/jarvis-app` on port 8788. Orchestra does not modify, replace or depend on it.
- **Telegram bot.** It stays as the fallback channel. Orchestra is additive.

## 5. Backend API contract

All routes except `/healthz` require the owner identity (D7). All responses are JSON unless stated.

| Method, path | Purpose |
|---|---|
| `GET /healthz` | `{"ok": true, "gateway": "up"\|"down"}`. No auth, no secrets, used by the keepalive. |
| `GET /api/models` | Models Hermes reports at `/v1/models`, cached 60 s. |
| `POST /api/chat` | Body `{conversation_id?, message, model?}`. Response: `text/event-stream` with `token`, `done` and `error` events. Records time to first token and total time. |
| `POST /api/chat/{id}/cancel` | Cancels an in-flight stream. |
| `GET /api/conversations`, `GET /api/conversations/{id}` | History. |
| `POST /api/tasks` | Body `{instruction, model?}`. Creates a background task and returns its id at once. |
| `GET /api/tasks`, `GET /api/tasks/{id}` | Task board: `queued`, `running`, `done`, `failed`, with the result. |
| `GET /api/stats` | Latency percentiles and gateway health, for the status bar. |

## 6. Screens

1. **Command:** a chat view with streaming output, a model picker, one-tap "run as background task", and cancel.
2. **Tasks:** the task board. Survives closing the app; results persist.
3. **Status bar,** always visible: gateway up or down, p50 time to first token over the last hour, running task count, and a link to the Hermes dashboard.

Mobile-first, dark theme, installable as a PWA. Nothing else in v1.

## 7. Not in v1

Public internet access; multiple users; voice input; Web Push notifications; editing Hermes config, keys or cron from Orchestra; calling models directly; replacing Telegram or JARVIS; any build tooling.

## 8. Unknowns that Phase 0 must settle, with evidence

1. Which endpoints the gateway API exposes, and in particular whether `POST /v1/chat/completions` exists and supports `stream: true`.
2. Whether a per-request `model` parameter is honoured, which decides whether per-request model choice exists at all.
3. How conversation state works: whether the client resends history, or the gateway keeps sessions.
4. Whether `python3 -m venv` and pip can install packages in the container.
5. Whether `tailscale serve --https` works in this userspace setup and passes `Tailscale-User-Login`.

If any answer breaks a settled decision, stop and ask the owner. That is an architecture change, not an implementation detail.
