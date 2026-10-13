# VPS inventory

Collected by `hos-step` (Q1), 2026-10-13. No IP addresses, hostnames,
usernames, or keys are recorded here.

## System

| Item | Value |
| --- | --- |
| OS | Debian GNU/Linux 13 (trixie) |
| Kernel | 6.8.0-139-generic |
| CPU | AMD EPYC 9354P, 2 cores |
| RAM | 7.8 Gi total, 2.4 Gi used, 5.4 Gi available |
| Swap | 0 B (none) |
| Disk `/` | 96 G total, 24 G used, 73 G free (25%) |
| Timezone | Etc/UTC (`/etc/localtime` → UTC) |

## Software

| Item | Value |
| --- | --- |
| hermes | v0.21.5 (2026.9.24), upstream f97608f1, installed via docker at /opt/hermes |
| docker | 26.1.5 |
| python3 | 3.13.5 |
| node | v26.5.1 |
| git | 2.47.3 |
| tailscale | missing |
| opencode | missing |

## Hermes configuration

- Config path: /opt/data/config.yaml, secrets: /opt/data/.env
- Main model: stepfun/step-5-preview:free (provider: nous,
  base_url redacted, api_mode chat_completions)
- Cron model: not separately set (falls back to default model)
- Reasoning: on · Terminal backend: local · Telegram configured, Discord not
- API keys: none of the listed integrations are set
