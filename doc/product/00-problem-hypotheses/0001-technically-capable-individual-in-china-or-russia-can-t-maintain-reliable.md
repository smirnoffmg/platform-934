---
id: PROB-0001
status: accepted
---

# A technically capable individual in China or Russia can't maintain reliable private internet access because commercial VPNs are centralized targets that censors systematically detect and block.

## Context

China's GFW and Russia's TSPU are distinct but converging censorship systems that have moved well beyond simple IP blocklists.

**China (GFW)** deploys ML-based passive traffic classification (entropy/popcount heuristics against "fully encrypted" traffic), active probing of suspect servers, JA3/TLS fingerprinting, QUIC SNI inspection (active since April 7, 2024, blocking ~43.8K FQDNs/week), and TCP RST injection. The September 2025 Geedge Networks leak confirmed the internal detection stack and revealed the system is being exported to Myanmar, Pakistan, Ethiopia, and Kazakhstan. Community-reported protocol "death dates" in 2025: Trojan ~90% detected, VMess ~80%, plain Shadowsocks flagged as fully-encrypted.

**Russia (TSPU)** blocks VPN protocols by DPI signature (OpenVPN, WireGuard, IKEv2, L2TP, PPTP are dead). Its most effective 2025–2026 tactic is the **"16 KB curtain"**: TLS 1.3/HTTPS-pattern connections to foreign datacenter IPs (Hetzner, DigitalOcean, OVH — exactly where Russians self-host) are frozen after ~25 packets (~16 KB), rendering them unusable regardless of protocol. As of June 2025 this affected Rostelecom, Megafon, Vimpelcom, MTS, and MGTS. TSPU's budget is nearly 60 billion rubles (~$660M) through 2030, targeting 96% VPN blocking efficiency. Regional "whitelist" mobile shutdowns (averaging 2,000/month as of Dec 2025, affecting 57 of 80+ regions) reduce the allowed destination set to ~57 state-approved sites.

**Commercial VPNs fail** because they are centralized: their server IP ranges are catalogued, their traffic is high-volume and pattern-detectable, and they cannot adapt per-user. A single technically capable user has structural advantages — low traffic volume, known client IPs, disposable server identities — that commercial providers cannot offer.

## Decision

This project accepts PROB-0001 as the primary problem to solve and builds toward a **self-hosted, single-user, censorship-resistant proxy provisioner** that:

1. Uses VLESS + XTLS-Vision + REALITY as the primary transport — it borrows a real third-party site's TLS 1.3 Server Hello (no cert required), defeating SNI blocking and active probing by transparently forwarding probes to the real destination.
2. Provides protocol fallbacks (AmneziaWG for Russia's UDP path; Hysteria2 for throughput on lossy links) on different ports.
3. Is deployed via an idempotent provisioner (Ansible + SOPS-encrypted secrets + templated configs) so a fresh server converges to a working state in one command and rotates port/SNI/IP in another.

The single-user constraint is a feature, not a limitation: it enables client-IP firewall whitelisting, low traffic volume (avoiding volume-based flags), and fast rotation without user coordination.

## Evidence

- **GFW active probing documented:** USENIX Security 2023 entropy/popcount classifier; GFW Report analysis of the September 2025 Geedge leak confirming Tiangou detection stack.
- **QUIC SNI inspection:** Zohaib et al., USENIX Security 2025 — GFW began blocking QUIC on April 7, 2024; one Initial packet can trigger blocking.
- **Russia 16 KB curtain:** Cloudflare official blog, June 26, 2025 ("Russian Internet users are unable to access the open Internet"); net4people/bbs #490 technical analysis confirming the ~25-packet/16 KB freeze heuristic targeting foreign datacenter IPs.
- **TSPU budget escalation:** Reuters, September 2025 — ~60B RUB allocated 2025–2030, explicit goal of 96% VPN blocking.
- **Whitelist shutdowns:** Carnegie Endowment (Maria Kolomychenko, Dec 2025); Mediazona (April 2026) — 57-site whitelist deployed in 57 of 80+ Russian regions.
- **Protocol death dates:** Community consensus (directional, not measured) — Trojan ~90% Aug 2025, VMess ~80% Sept 2025; VLESS+REALITY+Vision reported as current survivor.
- **REALITY active-probing defense:** XTLS/Xray-examples canonical docs; `aleskxyz/reality-ezpz` as production reference implementation.

## How we measure

- **Connectivity success rate:** REALITY tunnel completes a >1 MB transfer without freeze on both a China-routed and Russia-routed test path.
- **Active-probing survival:** Server responds correctly (forwards to real dest) when probed by a script mimicking GFW replay probes; no block within 72h of deployment.
- **Russia 16 KB curtain:** Transfer of >100 KB succeeds on the TSPU-affected ISP test path (Rostelecom or Megafon).
- **Deployment time:** `make deploy` on a fresh VPS converges to a working state in under 15 minutes unattended.
- **Rotation time:** `make rotate` (port/SNI/IP) completes and restores connectivity in under 5 minutes.
- **Fallback coverage:** At least one fallback protocol (AmneziaWG or Hysteria2) succeeds when the REALITY primary is blocked.

## Consequences

- **Accepted:** Scope is deliberately narrow — one user, two adversaries. Multi-user, multi-tenant, or commercial-scale use is out of scope and would negate the single-user structural advantages.
- **Accepted:** This is a cat-and-mouse domain. Any specific transport can be killed. The provisioner must make rotation cheap enough that a detected config is an operational inconvenience, not a failure.
- **Accepted:** Russia's whitelist-mode regional shutdowns have no technical solution within this scope (a domestic relay hop would be required). Degraded service during whitelist periods is accepted.
- **Risk:** IP/ASN reputation is as important as protocol choice in Russia. Provider selection (clean IP ranges, non-Hetzner/DO/GCP for Russia) is a deployment-time concern the provisioner can guide but not enforce.
- **Risk:** Legal exposure is real and rising in both jurisdictions (China MSS Nov 2025 warning; Russia VPN advertising criminalization Sept 2025). Out of scope for this project; user bears responsibility.
