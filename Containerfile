# Attacker image for labctl (hexstrike-kali:latest).
#
#   podman build -t hexstrike-kali:latest .
#
# HexStrike itself is third-party software: https://github.com/0x4m4/hexstrike-ai
# (MIT, Copyright (c) 2026 Muhammad Osama). This file only describes the
# tooling layer around it; copy the upstream server/MCP files in before building.
#
# Debian bookworm instead of Kali: identical tooling for this purpose, and
# Debian's mirrors don't suffer the rolling-release sync races Kali does.
FROM docker.io/library/debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# Lean, network-exploitation-focused arsenal.
# Full "kali-linux-headless" is ~4GB; this is the subset that matters for
# practising network + web-app exploitation inside a local lab.
RUN apt-get update && apt-get install -y --no-install-recommends \
        nmap \
        sqlmap \
        hydra \
        gobuster \
        dirb \
        whatweb \
        netcat-openbsd \
        curl \
        ca-certificates \
        dnsutils \
        python3 \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/hexstrike
COPY . /opt/hexstrike

# Trimmed dependency set: skip angr/pwntools (binary exploitation, ~1GB) and
# selenium (needs chrome) — irrelevant for network/web testing.
# --break-system-packages: this is a disposable container, PEP 668 isolation
# buys nothing here and Debian's venv module is unreliable in slim images.
RUN python3 -m pip install --no-cache-dir --break-system-packages \
        "flask>=2.3.0,<4.0.0" \
        "requests>=2.31.0,<3.0.0" \
        "psutil>=5.9.0,<6.0.0" \
        "fastmcp>=0.2.0,<1.0.0" \
        "beautifulsoup4>=4.12.0,<5.0.0" \
        "aiohttp>=3.8.0,<4.0.0" \
        "selenium>=4.15.0,<5.0.0" \
        "mitmproxy>=9.0.0"

# Bind to loopback only. HexStrike's /api/command executes arbitrary shell
# commands with NO authentication — never expose this on 0.0.0.0.
EXPOSE 8888
CMD ["python3", "hexstrike_server.py", "--port", "8888"]
