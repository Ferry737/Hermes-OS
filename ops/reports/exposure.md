# Exposure audit (Q2)

Read-only audit, run 2026-10-14 ~01:01 UTC on branch `hermes/loop`.

## Method

`ss` is **not installed** on this host, and neither is `netstat`, `lsof`,
`iptables`, `nft`, or `ufw` (checked with `which`). The listening sockets were
therefore read directly from `/proc/net/tcp` and `/proc/net/tcp6`, filtered to
state `0A` (LISTEN), and each socket inode was matched back to a PID by walking
`/proc/<pid>/fd/*` and reading the `socket:[inode]` links. Nothing was changed:
no service, no firewall, no process.

## Listening sockets

| Port | Bind | Process | Verdict |
|------|------|---------|---------|
| 4860 | `0.0.0.0` | `hermes dashboard --host 0.0.0.0 --port 4860 --no-open` (pid 140, up since 2026-10-08) | **PUBLIC** |
| 8644 | `0.0.0.0` | `hermes gateway run --replace` (pid 67426, up since 2026-10-13) | **PUBLIC** |
| 8644 | `::` | `hermes gateway run --replace` (same pid) | **PUBLIC** (IPv6, same socket) |
| 8642 | `127.0.0.1` | `hermes gateway run --replace` (same pid) | OK (loopback) |
| 20241 | `127.0.0.1` | `cloudflared tunnel --url http://127.0.0.1:8650 --no-autoupdate` | OK (loopback) |
| 20242 | `127.0.0.1` | `cloudflared tunnel --url http://127.0.0.1:8651 --no-autoupdate` | OK (loopback) |
| 20244 | `127.0.0.1` | `cloudflared tunnel --url http://127.0.0.1:8643 --no-autoupdate` | OK (loopback) |
| 41619 | `127.0.0.<docker-dns>` | not ours (Docker embedded DNS resolver, no PID visible in this namespace) | OK (loopback) |

Outbound-only connections (not listeners, IPs omitted): several ESTABLISHED and
TIME_WAIT sockets from the container network address on high ports toward port
443, belonging to `hermes gateway run`. These are outbound and are not an
exposure.

## Findings

1. **The dashboard listens on `0.0.0.0:4860`** — reachable from outside the
   host. It is running with `--host 0.0.0.0`, which the repo's own working rules
   forbid ("Never bind the dashboard to a public interface"). A local probe
   returns `302 Found` with `location: /login?next=%2F`, so there *is* a login
   wall in front of it, but it is still exposed to the internet or at minimum to
   whatever network this host sits on.
2. **The Hermes gateway listens on `0.0.0.0:8644` (IPv4 and IPv6)** — the same
   gateway process also holds a loopback listener on 8642, so the `0.0.0.0` bind
   is an additional public surface. A local probe to `/` returns `404 Not
   Found` (aiohttp), i.e. it is a live API surface, not a closed port.
3. **No host firewall is installed at all** — `ufw`, `iptables`, and `nft` are
   all missing. There is therefore no packet filter reducing the blast radius of
   either public bind; protection depends entirely on the provider's cloud-level
   firewall, which this audit cannot see.
4. **No SSH listener is visible in this namespace.** Port 22 does not appear in
   `/proc/net/tcp*`. This host appears to be a container, so `sshd` most likely
   lives on the host outside this namespace. That means the "public other than
   SSH" carve-out does not apply here: everything public in this namespace is
   something other than SSH.

## Verdict for tonight's report

**SECURITY: public port 4860** (dashboard, `0.0.0.0`)
**SECURITY: public port 8644** (Hermes gateway, `0.0.0.0` and `::`)

## Not done here

Per the item's *Done when* and the hard rules, nothing was changed: no service
restarted, no bind address edited, no firewall rule added. Rebinding the
dashboard to loopback and/or installing a host firewall is a `needs-ferry`
action (it takes a live service down and touches the host).
