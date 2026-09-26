# Orchestra TASKS

Work top to bottom, one task per turn, following `orchestra/PLAYBOOK.md` §4.
Check a box only when its **Done when** line is literally true, and paste the proof under it.
Tags: **[ANY]** any machine · **[VPS]** the Hermes container · **[OWNER]** needs the owner.
If a task is blocked, write why under it, leave it unchecked, and take the next one it doesn't block.

---

## P0. Establish the facts (read-only, blocking for P5 onward)

- [x] **P0.1 [VPS]** Map the gateway API. Search the installed source for its routes
  (`grep -rn "v1/" /opt/hermes --include=*.py | grep -iE "route|app\.(get|post)|path" | head -40`)
  and list every endpoint with method and auth requirement.
  *Done when:* `orchestra/docs/FACTS.md` has a "Gateway API" table, where each row quotes the source line it came from.
  - Proof: `orchestra/docs/FACTS.md` "Gateway API" section — table built from
    `_CAPABILITY_ENDPOINTS` (`/opt/hermes/gateway/platforms/api_server.py`
    lines 78–97), quote: `("chat_completions", ("POST", "/v1/chat/completions"))`,
    `("session_chat_stream", ("POST", "/api/sessions/{session_id}/chat/stream"))`.
    Plus live verification of /v1/capabilities, /v1/models, /api/model/options.
- [x] **P0.2 [VPS]** Test `POST /v1/chat/completions` with `stream: true`, a 10-word prompt and `max_tokens: 20`,
  loading the key inside the command (PLAYBOOK rule 5). Record the HTTP status, whether SSE `data:` chunks
  arrive, time to first chunk and total time (`curl -w`), with the output redacted to its shape.
  *Done when:* FACTS.md states streaming is "supported" or "not supported", with the quoted evidence.
  - Proof (FACTS.md "Streaming"): `status=200 ttfb_s=0.002168 total_s=3.055508`,
    7 `data:` chunks, final `data: [DONE]`. Streaming **supported**.
- [x] **P0.3 [VPS]** Pick two different model ids from `/v1/models` and send the same request with each.
  Compare the `model` field in the responses.
  *Done when:* FACTS.md states whether per-request model choice is "honoured" or "ignored", with evidence.
  - Proof (FACTS.md "Per-request model choice"): `/v1/models` lists only
    `['hermes-agent']` (one virtual entry), so the task as written has no two
    model ids to compare. The underlying question was settled by source +
    live test: bare `model` **ignored** (`model=zzz-bogus-nonexistent-model` →
    200, name echoed, default model answered; source `_request_agent_overrides`
    lines 343–365 + `direct_model_requests` default False at lines 1190–1191),
    `model` + `provider` together **honoured** (`openrouter/openrouter/free` +
    `provider=openrouter` → different model answered). `/api/model/options`
    lists 13 authenticated providers for the picker.
- [x] **P0.4 [VPS]** Find out how conversation state works (does the client resend history, or do headers or ids keep a session?)
  from the source found in P0.1.
  *Done when:* FACTS.md quotes the code path that decides it.
  - Proof (FACTS.md "Conversation state"): source `_derive_chat_session_id`
    (line 1044) derives the session from system prompt + first user message
    (sha256[:16], `api-` prefix). Live: same messages[0] → same
    `X-Hermes-Session-Id: api-a9b323cbe8dd9e66` and memory intact ("7741"
    recalled); different opening message → new session `api-cab07612ab4c79eb`,
    memory gone. Client resends history; gateway derives the session.
- [x] **P0.5 [VPS]** Test the Python tooling: `python3 --version; python3 -m venv /tmp/orch-venv && /tmp/orch-venv/bin/pip install --dry-run fastapi 2>&1 | tail -2; rm -rf /tmp/orch-venv`
  *Done when:* FACTS.md states whether a venv with pip can install from PyPI.
  - Proof (FACTS.md "Python tooling"): `Python 3.13.5`; venv created;
    `Would install ... fastapi-0.141.1 ... starlette-1.7.0`. Installs from PyPI: yes.
- [x] **P0.6 [VPS]** Record the current exposure baseline: `ps -eo args | grep -cE 'cloudflared|ngrok|localtunnel'`,
  `tailscale --socket=/opt/data/.tailscale/tailscaled.sock serve status`, and whether port 8790 is free
  (`grep -i ':2256 ' /proc/net/tcp /proc/net/tcp6`).
  *Done when:* FACTS.md has the three results, and `sh orchestra/ops/gates/exposure.sh` exits 0.
  - Proof (FACTS.md "Exposure baseline"): grep count 3 explained (all three
    matches are the grep pipeline's own wrapper lines; `grep -v grep` → empty,
    no real tunnel process); `serve status` shows three tailnet-only rules
    (8788, 8642, https 8900), no Funnel; port 8790 free; exposure gate →
    "exposure gate clean", exit 0.
- [x] **P0.7 [ANY]** Compare FACTS.md with SPEC §3 and §8. For every settled decision a fact contradicts,
  write the conflict and the smallest change that would resolve it.
  *Done when:* FACTS.md ends with "Spec conflicts: none", or with a list. **If there is a list, stop the loop and ask the owner.**
  - Proof: FACTS.md final section — "Spec conflicts: none". D1–D10 all
    survive. Two implementation notes filed for P2/P3 (model picker sources
    `/api/model/options`; requests send `provider`+`model` together) — within
    the spec, not conflicts.

## P1. Backend skeleton

- [ ] **P1.1 [ANY]** Create `orchestra/backend/` with `pyproject.toml` (fastapi, uvicorn, httpx; pytest as a dev extra),
  `app/config.py`, `app/main.py` with `GET /healthz`, and the JSON access-log middleware (PLAYBOOK §6).
  *Done when:* `cd orchestra/backend && python -m pytest -q` passes a test proving `/healthz` returns 200 and that a log line contains no headers.
- [ ] **P1.2 [ANY]** Add the identity guard (SPEC D7): every `/api/*` route requires `Tailscale-User-Login == ORCHESTRA_OWNER_LOGIN`.
  *Done when:* tests prove a missing header gives 401, a wrong login gives 403, and the right login passes.
- [ ] **P1.3 [ANY]** Write `app/gateway.py`: it reads the key from `ORCHESTRA_ENV_FILE`, calls `/v1/models`, caches the result for 60 s, and times out after 5 s.
  Add `GET /api/models`, and a stub gateway fixture for the tests.
  *Done when:* tests prove the models are returned, the cache is used, a gateway outage returns 502 without upstream text, and the key never appears in a response or log (asserted).

## P2. Streaming chat (depends on P0.2 for the exact upstream format)

- [ ] **P2.1 [ANY]** Build `POST /api/chat`: forward to the gateway with streaming and re-emit `token`/`done`/`error` SSE events.
  Record time to first token and total time in SQLite (SPEC D8).
  *Done when:* a test against a stub streaming gateway receives the tokens in order, and a latency row is written.
- [ ] **P2.2 [ANY]** Store conversations and messages, and add `GET /api/conversations[/{id}]`. Follow the state model found in P0.4.
  *Done when:* a test proves a second message in the same conversation carries the context that P0.4 says is required.
- [ ] **P2.3 [ANY]** Add cancel (`POST /api/chat/{id}/cancel`), which closes the upstream stream.
  *Done when:* a test proves the upstream connection closes within 1 s of the cancel.
- [ ] **P2.4 [ANY]** Honour a per-request `model` only if P0.3 said "honoured". Otherwise reject the field with a clear 400.
  *Done when:* a test covers whichever branch P0.3 selected.

## P3. Background tasks ("your employee")

- [ ] **P3.1 [ANY]** Build `POST /api/tasks` and `GET /api/tasks[/{id}]`: a worker in the same process runs queued tasks one at a time and stores the result.
  *Done when:* a test posts a task, the stub gateway completes it, and the status goes `queued → running → done` with the result stored.
- [ ] **P3.2 [ANY]** Make tasks restart-safe: on startup, tasks left `running` become `failed` with the reason "interrupted by restart" (never silently lost).
  *Done when:* a test simulates the restart and proves it.

## P4. Frontend (no build step)

- [ ] **P4.1 [ANY]** Build the `orchestra/web/` shell: Command view, Tasks view, status bar (SPEC §6), mobile-first dark theme, served by the backend at `/`.
  *Done when:* a test fetches `/`, `/app.js` and `/style.css` with status 200, and `grep -rE 'API_SERVER_KEY|hsk_|sk-' orchestra/web` finds nothing.
- [ ] **P4.2 [ANY]** Wire streaming chat, the model picker (hidden if P0.3 said "ignored"), "run as task", and cancel.
  *Done when:* a Playwright check (if Chromium is available; otherwise a scripted SSE client test) sends a message to the stub and sees the streamed text rendered.
- [ ] **P4.3 [ANY]** Add the PWA manifest and a service worker that caches only the shell (SPEC D10).
  *Done when:* a test asserts `sw.js` contains no `/api/` cache route and the manifest parses as JSON.

## P5. Deploy on the VPS

- [ ] **P5.1 [VPS]** Write `orchestra/deploy.sh`: copy `backend/` and `web/` to `/opt/data/orchestra/app`, create or refresh the venv,
  write `/opt/data/orchestra/orchestra.env` (non-secret settings, including `ORCHESTRA_OWNER_LOGIN`), and (re)start uvicorn on `127.0.0.1:8790`, logging to `/opt/data/orchestra/logs/`. It must be idempotent. `--start-only` skips the copy and venv steps (used by the keepalive).
  *Done when:* running it twice leaves exactly one uvicorn process, and `curl -s 127.0.0.1:8790/healthz` returns `"ok": true`.
- [ ] **P5.2 [VPS]** Add an Orchestra block to `/opt/data/services_keepalive.sh` in the same style as the existing ones:
  a real `curl /healthz` check, and a restart via `deploy.sh --start-only`.
  *Precondition:* the current script's content is quoted first. *Stop if:* the script differs from what was last approved.
  *Done when:* killing uvicorn by hand results in it coming back within one cron tick (quote `keepalive.log`).
- [ ] **P5.3 [VPS]** Serve it on the tailnet: `tailscale --socket=/opt/data/.tailscale/tailscaled.sock serve --bg --https=8443 http://127.0.0.1:8790`.
  *Done when:* `serve status` shows the rule, and the exposure gate exits 0.
- [ ] **P5.4 [VPS]** Verify the identity header: log only the *presence* of `Tailscale-User-Login` (never its value) for one tailnet request.
  If it is absent, implement the passcode fallback from SPEC D7 before continuing.
  *Done when:* the log shows `identity_header=present`, or the fallback is shipped and tested.
- [ ] **P5.5 [VPS]** `echo 2 > orchestra/ops/.phase`
  *Done when:* `sh orchestra/ops/gates/smoke.sh` exits 0 at phase 2.

## P6. Prove the speed

- [ ] **P6.1 [ANY]** Write `orchestra/bench/bench.py`: 3 fixed prompts × 5 runs, each measured directly against the gateway and through Orchestra,
  reporting time-to-first-token and total at p50/p95. It runs only when invoked by hand (it costs tokens).
  *Done when:* it runs against the stub and prints a table.
- [ ] **P6.2 [VPS]** Run the benchmark for real. Write the table into `orchestra/docs/BENCH.md`.
  *Done when:* BENCH.md shows Orchestra overhead ≤ 100 ms at p50, or explains why not and names the fix.
- [ ] **P6.3 [OWNER]** Owner: send the same 3 prompts on Telegram and time seconds-to-first-visible-reply with a stopwatch. Add the numbers to BENCH.md.
  *Done when:* both columns are filled. Only now may anyone write "faster than Telegram".

## P7. Owner acceptance

- [ ] **P7.1 [OWNER]** On the phone: open `https://<host>.<tailnet>.ts.net:8443`, install it to the home screen, send one command, start one background task,
  lock the phone, and come back later to find the result waiting.
  *Done when:* the owner confirms all five steps in writing.
- [ ] **P7.2 [VPS]** Rebuild drill: after the next container rebuild (or a manual `docker restart` by the owner), Orchestra comes back without anyone touching it.
  *Done when:* `keepalive.log` shows the restart, and `/healthz` returns ok.
