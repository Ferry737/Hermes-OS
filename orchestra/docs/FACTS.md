# FACTS — what Phase 0 proved about the gateway (2026-09-26)

Every row quotes the source line or live command output it came from. Affects
SPEC §8 unknowns 1–5 and the P2/P3 task definitions. Live probes were run
against `http://127.0.0.1:8642` with `API_SERVER_KEY` from `/opt/data/.env`
loaded inside the command, never displayed.

## Gateway API

Auth: every endpoint requires `Authorization: Bearer <API_SERVER_KEY>`; the
registered capabilities table in `/opt/hermes/gateway/platforms/api_server.py`
lists the endpoints (lines 78–97, `_CAPABILITY_ENDPOINTS`):

| Method, path | Purpose (from source) |
|---|---|
| GET /health, /health/detailed | health probes (same file, `_CAPABILITY_ENDPOINTS`) |
| GET /v1/models | model catalog (verified live: 1 entry) |
| GET /v1/capabilities | feature flags (verified live: streaming, runs API) |
| POST /v1/chat/completions | OpenAI-compatible chat (verified live, below) |
| POST /v1/responses | Responses API (capabilities: `"responses_api": true`) |
| POST /v1/runs | background run submission (capabilities: `"run_submission": true`) |
| GET /v1/runs/{run_id} | run status (capabilities: `"run_status": true`) |
| GET /v1/runs/{run_id}/events | SSE events (capabilities: `"run_events_sse": true`) |
| POST /v1/runs/{run_id}/stop | cancel (capabilities: `"run_stop": true`) |
| POST /v1/runs/{run_id}/steer | mid-run steering (capabilities: `/v1/runs/{run_id}/steer` row) |
| GET /v1/skills, /v1/toolsets | catalogs |
| GET /api/sessions, POST /api/sessions | list/create sessions |
| GET /api/sessions/{id}, PATCH, DELETE | session management |
| GET /api/s/api/sessions/{id}/messages | message history |
| GET /api/sessions/{id}/fork, POST | fork |
| POST /api/sessions/{id}/chat, /chat/stream | non-streaming + SSE chat |
| POST /api/sessions/{id}/model | per-session model lock |
| GET /api/model/options | model picker data (verified live: 57 providers, 13 authenticated, OpenRouter free pool 458 models) |
| POST /v1/browser-control/register, GET /v1/browser-control/ws | browser control |
| POST /v1/artifacts/upload, GET /v1/artifacts/download/{id} | artifacts |

Not verified live: every row marked "(from source)" where no live probe ran.
The `max_tokens` on the file counts: 4311 lines (`wc -l`).

## Streaming (SPEC §8.1)

**Supported.** Live test `curl -sS -N` POST /v1/chat/completions with
`"stream": true`, `max_tokens: 20`:
`status=200 ttfb_s=0.002168 total_s=3.055508`, 7 `data:` chunks, final
`data: [DONE]`. Delta shapes seen: `delta: {"role": "assistant"}`, then
`delta: {"reasoning_content": ...}` and `delta: {"content": ...}` — P2.1 must
pass both keys through, not just `content`.

## Per-request model choice (SPEC §8.2)

**Honoured only with explicit `provider`; bare `model` is ignored.**

- `/v1/models` live: `['hermes-agent']` — one virtual model entry.
- `_request_agent_overrides` (source lines 343–365): `provider` is always
  honoured; bare `model` honoured only when `allow_bare_model` and the
  OpenAI-compatible handlers pass `direct_model_requests` (line 1190–1191:
  `self._direct_model_requests: bool = _coerce_request_bool(extra.get("direct_model_requests"), default=False)`)
  — not set in config (`platforms.api_server` is `{}`), so default False.
- Live proof: `model=zzz-bogus-nonexistent-model` → 200 with the name echoed
  but the default model answered; `model=openrouter/openrouter/free` +
  `provider=openrouter` → different model answered (behavioral change).
- `/api/model/options` live: 57 providers, 13 authenticated (Nous Portal,
  OpenRouter, Anthropic, NVIDIA NIM, GitHub Copilot, Google AI Studio,
  Z.AI/GLM, Ollama Cloud, Kilo Code, OpenRouter free pool, Mistral free).
  The model picker should use this endpoint, not /v1/models.

## Conversation state (SPEC §8.3)

**Client resends full history; gateway derives the session.**

- Source: `_derive_chat_session_id(system_prompt, first_user_message)` at
  line 1044: `"Stable session id from the system prompt + first user message
  (constant across all turns of an Open WebUI-style conversation)"` — sha256
  of `f"{system_prompt or ''}\n{first_user_message}"`[:16], prefixed `api-`.
- Live proof: turn 1 "My code is 7741..." → header `X-Hermes-Session-Id:
  api-a9b323cbe8dd9e66`. Turn 2 with a different opening message → new
  session `api-cab07612ab4c79eb`, memory gone ("I don't have a code"). Turn 2
  resending messages[0] + follow-up → same `api-a9b323cbe8dd9e66`, memory
  intact (answered "7741").
- Alternative: the native session API keeps server-side state explicitly
  (POST /api/sessions → id, then POST /api/sessions/{id}/chat[/stream]) —
  a stronger fit for Orchestra conversations than history-resend (see
  PROPOSALS.md).

## Python tooling (SPEC §8.4)

**Works.** `python3 --version` → `Python 3.13.5`;
`python3 -m venv /tmp/orch-venv` OK; `pip install --dry-run fastapi` →
`Would install ... fastapi-0.141.1 ... starlette-1.7.0`. PyPI reachable.

## Exposure baseline (SPEC §8.5)

- `ps -eo args | grep -cE 'cloudflared|ngrok|localtunnel'` → 3, but all three
  matches are the grep pipeline's own shell wrapper lines (verified by
  `ps -eo args | grep -E ... | grep -v grep` → empty). No real tunnel process.
- `tailscale serve status` (via `/opt/data/.tailscale/tailscaled.sock`): three
  tailnet-only rules — 8788 (JARVIS), 8642 (gateway), https 8900 (unnamed
  HTTPS app). No Funnel, nothing public.
- Port 8790: free (`grep -i ':2256 ' /proc/net/tcp /proc/net/tcp6` → no match).
- `sh orchestra/ops/gates/exposure.sh` → "exposure gate clean", exit 0.

## Spec conflicts: none

Every settled decision D1–D10 survives Phase 0. The model picker in SPEC §6
should source from `/api/model/options` (13 authenticated providers) instead
of `/v1/models` (1 virtual entry), and requests should send `provider`+`model`
together — an implementation choice within the spec, filed as PROPOSALS.md
items, not conflicts.

## Bonus fact for P3

`POST /v1/runs` + `GET /v1/runs/{id}/events` (SSE) + stop/steer is the
gateway's own background-run machinery. Orchestra's task board can back onto
it rather than reimplementing run management in Orchestra's worker. Filed as
a proposal for P3; not a spec conflict.
