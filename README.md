# Local network-exploitation lab

A deliberately vulnerable host and an attacker box, both in rootless podman, on a
private bridge network with **no published ports**. Nothing in the lab is
reachable from your LAN or the internet.

This exists because network exploitation needs a network you own. Pointing these
tools at someone else's host is a crime regardless of intent, and pointing them
gets you banned from the program.

> Scope: Metasploitable 2 is 2008-era and intentionally broken. Everything here is
> disposable. Do not reuse these containers, images, or configs for anything real.

## What's in here

| File | What it is |
|---|---|
| `labctl` | The whole lab. Bash script that creates/destroys the network and containers. No other entrypoint. |
| `Containerfile` | Builds the attacker image (`hexstrike-kali:latest`): Debian + nmap/sqlmap/hydra/gobuster/dirb/whatweb + HexStrike. |
| `README.md` | This file. |
| `.gitignore` | Keeps scan output, captures, and credentials out of git. |

There is no application code, no build system, and no state. `labctl` is the
entire interface; everything else is derived from it.

## Prerequisites

- `podman` (rootless; no daemon, no root)
- `bash`, `curl`
- ~3 GB free disk for the two images
- `nmap` on the host is **not** required — `./labctl scan` runs it inside the attacker container

## Quick start

```bash
git clone <this-repo> lab && cd lab
./labctl start        # bring up victim + attacker (~15s for services)
./labctl status       # IPs and open ports
./labctl scan         # nmap -sT -sV against the victim
./labctl shell        # shell into the attacker container
./labctl stop         # tear it all down
```

## Building the attacker image

`labctl` expects `hexstrike-kali:latest` to exist locally. It is not pulled from a
registry, so build it once:

```bash
# 1. Upstream HexStrike (MIT, https://github.com/0x4m4/hexstrike-ai)
git clone https://github.com/0x4m4/hexstrike-ai ~/tools/hexstrike-ai

# 2. Build with this repo's Containerfile (it expects hexstrike_server.py next to it)
cp Containerfile ~/tools/hexstrike-ai/
cd ~/tools/hexstrike-ai
podman build -t hexstrike-kali:latest .
```

The victim image `docker.io/tleemcjr/metasploitable2` is pulled on first `start`.
It is a community repackage of the official Metasploitable 2 VM, not a vendor
image — pin it by digest if you care about reproducibility.

## Topology

```
        host (your machine)
              |
        [ hslab network, 10.89.1.0/24 ]   <-- podman bridge, no host exposure
         /                          \
  hslab-attacker               hslab-victim
  hexstrike-kali:latest        metasploitable2
  nmap sqlmap hydra            ftp ssh telnet http smb mysql
  gobuster dirb whatweb        (intentionally vulnerable services)
```

Only exception: `labctl hexstrike` publishes port 8888 **to 127.0.0.1 only**,
because HexStrike's `/api/command` endpoint runs arbitrary shell commands with no
authentication.

## Commands

| Command | Does |
|---|---|
| `./labctl start` | Create network, start victim + attacker, wait for services |
| `./labctl stop` | Remove attacker, victim, HexStrike, and the network |
| `./labctl status` | Containers, victim IP, which ports answer from the attacker |
| `./labctl scan` | `nmap -sT -sV -Pn` against the victim |
| `./labctl shell` | Shell into the attacker container |
| `./labctl hexstrike` | Start HexStrike API on `127.0.0.1:8888` |
| `./labctl victim-ip` | Print the victim's lab IP |

## What to actually practise

The victim is Metasploitable 2. It is a 2008-era Linux box with a dozen known
vulnerabilities. The loop that teaches you something:

1. **Enumerate** — `nmap -sT -sV -Pn <ip>`, then per-service probes
   (`nmap -sT -p 139,445 --script smb-enum-shares <ip>`).
2. **Fingerprint** — `whatweb http://<ip>`, `dirb http://<ip>`, `curl -I`.
3. **Match to a known CVE** — vsftpd 2.3.4 backdoor on port 21, the Samba
   `usermap_script` RCE on 139/445, the distcc RCE on 3632, the phpMyAdmin and
   DVWA web apps on 80.
4. **Exploit in the lab** — `searchsploit`, then Metasploit or a PoC. Watch what
   the packet does; that's the lesson, not the shell.
5. **Write it down** — command, output, why it worked, what a fix looks like.

Then go back to a real program with the mental model: enumerate first, and ask
"did the server refuse, or did only the UI refuse?"

## Driving HexStrike

`./labctl hexstrike` starts the API on `127.0.0.1:8888` inside a container on the
`hslab` network, so it already has nmap/sqlmap/hydra/gobuster/dirb/whatweb on PATH.
Two ways to use it:

```bash
# 1. Health + tool inventory
curl -s http://127.0.0.1:8888/health | jq '{status, tools_status}'

# 2. Run a tool through the API
curl -s -X POST http://127.0.0.1:8888/api/command \
  -H 'Content-Type: application/json' \
  -d "{\"command\":\"nmap -sT -sV -Pn $(./labctl victim-ip)\"}" | jq -r '.stdout'
```

The second call is why port 8888 is bound to loopback: **anyone who can reach
that port can run any command in the container.** Never publish it.

The container also mounts `$HOME/.local/bin` read-only at `/opt/hostbin` so
HexStrike's tool detection finds the host's Go-built binaries. That directory is
readable by anything that reaches `/api/command` — point the mount at a dedicated
`./tools/bin` instead if your `~/.local/bin` holds anything private.

The MCP side (`hexstrike_mcp.py`) is what an LLM client talks to. If you want
that, run it on the host with the venv in `~/tools/hexstrike-ai/.venv` and point
it at `http://127.0.0.1:8888`. It is a convenience layer — the commands it
issues are the same ones you'd type.

## Isolation: what it does and doesn't protect against

- **No inbound exposure.** No ports are published except 8888, which is bound to
  loopback. Nothing on your LAN or the internet can reach the victim.
- **Outbound is not blocked.** Podman's bridge NATs to the host, so the attacker
  container can reach the internet and your LAN. It is not an airgap. If you want
  one, create the network with `--internal` (breaks package installs, so do it
  after the images are built).
- **Not a VM.** Rootless podman shares the host kernel. The victim is deliberately
  exploitable; treat any successful escape as a host compromise.
- **Port 8888 is an unauthenticated RCE endpoint** by design. It is meant to live
  for the duration of one exercise.

## Rules

- Never add `-p 0.0.0.0:...` to the victim. It is intentionally exploitable.
- Never point these tools at a host you do not own or have written permission
  for. `bughunter-guard` enforces this for the bounty workspace; this lab
  deliberately bypasses it because the target is local and disposable.
- Destroy and rebuild freely: `./labctl stop && ./labctl start`.

## Attribution

`Containerfile` builds around [HexStrike AI](https://github.com/0x4m4/hexstrike-ai)
by Muhammad Osama (0x4m4), MIT licensed. Metasploitable 2 is by Rapid7. The
`labctl` script and this README are original to this repo.
