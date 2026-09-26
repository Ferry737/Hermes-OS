# Running the Orchestra loop

Two ways to run it. They share the same task list, playbook and gates, so either one (or both, taking turns) produces the same result.

| Runner | Can do | Cannot do |
|---|---|---|
| **Hermes Agent on the VPS** (`/goal`) | Everything tagged [ANY] and [VPS] | [OWNER] tasks |
| **Claude Code** (`/loop`) | Everything tagged [ANY]: all the code and tests | [VPS] and [OWNER] tasks: it has no access to your server |

Recommended split: let Claude Code build P1–P4 (code plus tests), then let Hermes run P0 and P5–P6 on the VPS. P0 is read-only and can run first, in parallel.

---

## A. Hermes Agent on the VPS

### 1. Once, before starting

```sh
cd /opt/data/hermes-cockpit
git fetch origin claude/hermes-fintech-agent-profile-v241hj
git checkout -B orchestra-build origin/claude/hermes-fintech-agent-profile-v241hj
chmod +x orchestra/ops/gates/*.sh ops/gates/secrets.sh
echo 0 > orchestra/ops/.phase
hermes config set goals.max_turns 40
```

### 2. Gates (they run before the judge, every turn, in this order)

```
/goal gate add sh orchestra/ops/gates/budget.sh
/goal gate add sh orchestra/ops/gates/exposure.sh
/goal gate add sh ops/gates/secrets.sh
/goal gate add sh orchestra/ops/gates/tests.sh
/goal gate add sh orchestra/ops/gates/smoke.sh
```

The budget gate comes first so the circuit breaker trips before anything expensive runs. Exposure comes second, because a public port outranks every other problem.

### 3. The goal (paste as one message, newlines included)

```
/goal Build Orchestra exactly as specified in orchestra/SPEC.md by completing orchestra/ops/TASKS.md in order, following orchestra/PLAYBOOK.md on every turn.
verify: every [ANY] and [VPS] task in orchestra/ops/TASKS.md is checked with quoted proof under it; every [OWNER] task carries written instructions for the owner; `sh orchestra/ops/gates/tests.sh`, `sh orchestra/ops/gates/exposure.sh` and `sh orchestra/ops/gates/smoke.sh` all exit 0; the work is committed
constraints: read orchestra/PLAYBOOK.md in full before the first task and its §4 checklist before every task; report in the PLAYBOOK §5 format only; never print a secret or any part of one; never bind anything to a non-loopback address; never start cloudflared, ngrok, localtunnel or Tailscale Funnel; never put an IP, tailnet hostname or key in a tracked file; never edit /opt/hermes, Hermes config or keys, JARVIS, or cron jobs other than services-keepalive; settled decisions in SPEC §3 are fixed, so write disagreements in orchestra/docs/PROPOSALS.md and keep building to the spec; never force-push; never rewrite or delete a task to make it pass
boundaries: orchestra/ in this repo, /opt/data/orchestra/, one Orchestra block in /opt/data/services_keepalive.sh, one tailscale serve rule on port 8443
stop when: P0.7 lists spec conflicts; a task needs a credential or account you do not have; the same task fails three turns running; the exposure gate is red and undoing your own last change does not make it green; an action would change a settled decision
```

### 4. Watching it

```
/goal status      where it is and how many turns it has used
/goal gate        which gates are green
/goal pause       stop, keep the goal
/goal resume      continue and reset the turn counter
```

When it pauses on the budget gate, read the diff before resuming. That pause is deliberate.

---

## B. Claude Code (code and tests only)

In a Claude Code session on this repository, run:

```
/loop Work the Orchestra build loop. Read orchestra/PLAYBOOK.md in full, then take the first unchecked [ANY] task in orchestra/ops/TASKS.md and complete it exactly as the playbook's §4 checklist says: tests in the same commit, all four gates green (sh orchestra/ops/gates/exposure.sh && sh ops/gates/secrets.sh && sh orchestra/ops/gates/tests.sh && sh orchestra/ops/gates/smoke.sh), box checked with quoted proof, one commit per task naming the task id, push. For [VPS] or [OWNER] tasks, write "needs VPS" or "needs owner" under them and move on. Report in the playbook §5 format. When no unchecked [ANY] task remains, report that and stop the loop.
```

The `orchestra-builder` skill in `.claude/skills/` loads the playbook automatically whenever a Claude session works on Orchestra.

---

## C. What you (the owner) will be asked to do

About 20 minutes in total, spread over the build:
- **P0.7:** only if a fact contradicts the spec. You'll get one clear question.
- **P6.3:** time 3 prompts on Telegram with a stopwatch.
- **P7.1:** install the app on your phone and try it.

Everything else runs without you.
