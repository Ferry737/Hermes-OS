---
name: orchestra-builder
description: Use when working on Orchestra, the private web app that sends commands to the owner's Hermes Agent on the VPS (anything under orchestra/, its tasks, gates, deployment, or speed benchmark). Loads the working method so every session builds the same system the same way.
---

# Orchestra builder

Before doing anything on Orchestra:

1. Read `orchestra/PLAYBOOK.md` in full. It is the working method and it overrides your habits.
2. Read `orchestra/SPEC.md` §3 (the settled decisions). Do not change them. Put disagreements in `orchestra/docs/PROPOSALS.md`.
3. Take the first unchecked task you can run from `orchestra/ops/TASKS.md` (see the tags in PLAYBOOK §3; a cloud session can only do [ANY] tasks).
4. Follow the PLAYBOOK §4 checklist exactly, including all four gates:
   `sh orchestra/ops/gates/exposure.sh && sh ops/gates/secrets.sh && sh orchestra/ops/gates/tests.sh && sh orchestra/ops/gates/smoke.sh`
5. Report in the PLAYBOOK §5 format.

Non-negotiables: never print a secret or any part of one; never make anything public; never claim anything you haven't proved with quoted output; one task per commit, with the task id in the message.
