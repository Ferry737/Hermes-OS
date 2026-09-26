# Orchestra Playbook — how to do this work

This file teaches any model (Claude, Hermes, or another) how to build and run Orchestra the way it was designed. The owner should get the same result no matter which model runs the loop. Read it in full before your first task, and re-read the "Every turn" checklist before each task.

The spec says **what** to build (`orchestra/SPEC.md`). The task list says **what's next** (`orchestra/ops/TASKS.md`). This file says **how to work**.

---

## 1. The twelve rules

**1. Truth before momentum.** Every claim you make about the system carries evidence: the command you ran and its output, quoted. "I don't know yet" is an acceptable answer. A confident guess is not. Never invent a fact about Hermes. Learn it from the installed source (`/opt/hermes`), the docs at hermes-agent.nousresearch.com/docs, or a live request, and quote what you found.

**2. Read before you write.** Discovery is read-only. Look at the current state of a file, process, port or config before changing it, and quote what you saw.

**3. Every change to the server has a precondition and a stop condition.** Write both down before acting, for example: "Restart only if `s6-svstat` shows the same PID as the gateway process. Otherwise stop and report." If the precondition fails, stop. Do not improvise a different destructive action.

**4. Test the live state, not your assumption.** Before a fix, prove the problem exists. After a fix, prove it is gone. Example from 2026-09-25: a planned gateway restart turned out to be unnecessary, because a live auth test showed the new key already worked (`new:200 old:401`).

**5. Secrets never appear.** Not in chat, logs, commits, tests, fixtures or error messages, not even as a prefix. Load them inside the command that uses them: `KEY=$(grep '^API_SERVER_KEY=' /opt/data/.env | cut -d= -f2-)`. Check them by count, never by display: `grep -c`. Tracked files use placeholders such as `<VPS_IP>`, `<host>.<tailnet>.ts.net` and `<owner-login>`. If you print a secret by accident, say so immediately and tell the owner it needs rotating. Never write "no secret was displayed" unless you have checked your own output.

**6. Nothing is public.** Bind to `127.0.0.1`. Reach services through `tailscale serve` on the tailnet only. Never start cloudflared, ngrok, localtunnel or Funnel. Keys live in the backend, never in the browser. `orchestra/ops/gates/exposure.sh` enforces this. If it goes red, fixing it comes before anything else.

**7. One task per turn, done means done.** Take the first unchecked task you are able to run (see §3). Check its box only when its **Done when** line is literally true and you can quote the proof. One task, one commit, with the task id in the message (`P2.1: stream chat tokens over SSE`).

**8. Measure claims.** "Faster", "works" and "secure" are numbers or command outputs, never adjectives. Speed claims go into `orchestra/docs/BENCH.md` with the method, sample size and p50/p95.

**9. Build the smallest thing that meets the spec.** Reuse what Hermes already does. Add no dependency without a one-line reason in the commit. Add no features beyond the spec. Ideas go in `orchestra/docs/PROPOSALS.md`.

**10. Review your own diff as its enemy before committing.** Ask what would make it fail, leak a secret, expose a port, or break after a container rebuild, then fix what you find. Run the tests and gates yourself; don't leave that to the loop.

**11. Escalate decisions, not problems.** Solve problems yourself. Hand decisions to the owner: anything that changes a settled decision in SPEC §3, spends money beyond the benchmark, deletes data, or touches anything outside the scope in §4. After three failures on the same task, write what you tried and the exact error into `orchestra/ops/BLOCKED.md` and move to the next task. Do not attempt a fourth approach.

**12. Report the same way every time** (see §5). The owner is a non-technical founder. Lead with the outcome in one sentence, then the evidence, then the single decision you need from them, if any.

## 2. Mistakes this loop is designed to prevent

These all happened on 2026-09-24/25. They are calibration examples, not blame.

| What a model did | Why it was wrong | What the rule requires |
|---|---|---|
| Called a 1,522-line file "200+ pages" | Unchecked estimate | `wc -l` before describing size |
| Wrote "no process listening" next to a `401` it had just received | A 401 proves a listener | Reconcile contradictory evidence before reporting |
| Wrote "never printed" and printed the key in the same sentence | It never checked its own output | Rule 5 |
| Called the machine "not a container" from `0::/` | Weak evidence read as proof | Use decisive checks (`/.dockerenv`, PID 1 name) |
| Said a config file held the key at "line 256" | The file had no such line | Quote, don't paraphrase |
| Kept a keepalive that grepped `/proc/net/tcp` | It reported "alive" for a dead service | Health checks make a real request |

## 3. Where a task can run

Every task in TASKS.md is tagged with where it can be done:

- **[ANY]:** code and tests. Any machine with Python 3.11+, including a Claude Code cloud session.
- **[VPS]:** needs the Hermes container: `/opt/data`, the gateway on 8642, tailscale. If you are not on the VPS, write `needs VPS` under it and move on. This is not a failure.
- **[OWNER]:** needs the owner's phone, eyes or accounts. Write what they must do in one short paragraph under the task, then move on. Never simulate an owner check.

How to tell whether you are on the VPS: `test -f /opt/data/.env && test -d /opt/hermes && echo VPS`.

## 4. Every turn (checklist)

1. `git pull`, then read `orchestra/ops/TASKS.md` and pick the first unchecked task you can run.
2. Re-read the SPEC sections that the task names.
3. If it changes the server: write its precondition and stop condition (rule 3).
4. Do the work. Code tasks ship with tests in the same commit.
5. Run the gates yourself: `sh orchestra/ops/gates/exposure.sh && sh ops/gates/secrets.sh && sh orchestra/ops/gates/tests.sh && sh orchestra/ops/gates/smoke.sh`
6. Review the diff as its enemy (rule 10). Fix what you find, then re-run step 5.
7. Check the box and paste the proof under the task (a short quote, secrets redacted).
8. Commit (task id in the message) and push.
9. Report (§5).

## 5. Report template

```
<task id>: <done | blocked | needs VPS | needs owner>. <one-sentence outcome>

Evidence:
<the command(s) and quoted output that prove the Done-when line>

Changed: <files or server state, one line each>
Not verified: <anything you could not prove, or "nothing">
Owner decision needed: <one question, or "none">
```

No motivational summaries, no video scripts, no emoji dashboards. The owner reads the evidence.

## 6. Stack conventions (so every model writes the same code)

- Python 3.11+, type hints, `from __future__ import annotations`. FastAPI app in `orchestra/backend/app/`. Tests with pytest in `orchestra/backend/tests/`, against a stub gateway (never the real one, never real keys).
- Config comes from environment variables with the prefix `ORCHESTRA_`, read in one module (`app/config.py`). The API key comes from `ORCHESTRA_ENV_FILE` (default `/opt/data/.env`), key `API_SERVER_KEY`.
- The gateway client is one module (`app/gateway.py`) that owns every call to Hermes. Nothing else imports httpx for that purpose.
- Frontend in `orchestra/web/`: `index.html`, `app.js` (ES modules), `style.css`, `manifest.webmanifest`, `sw.js`. No build step. No inline secrets. No third-party scripts.
- Logs are one JSON line per request (method, path, status, ms), with no bodies and no headers.
- Error messages shown to the user never include stack traces or upstream response bodies.

## 7. Scope

In scope: `orchestra/` in this repository; `/opt/data/orchestra/` on the VPS; one added block in `/opt/data/services_keepalive.sh`; one `tailscale serve` rule on port 8443.

Out of scope: everything else, including `/opt/hermes`, Hermes config and keys, JARVIS, other cron jobs, other serve rules, and the rest of this repository.
