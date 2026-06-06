# Censorship-Resistant Single-User VPN/Proxy for China and Russia (2026): Architecture, Threat Model, and Repo Design

## TL;DR

- **Build on Xray-core, and make VLESS + XTLS-Vision + REALITY on TCP/443 your primary transport** — it is the consensus gold standard for Great Firewall resistance in 2026 because it borrows a real third-party site's TLS handshake (no cert needed), defeats SNI-based blocking, and survives active probing by transparently proxying probes to the real target site. Run a second protocol (AmneziaWG or Hysteria2) as a fallback on a different port.
- **China and Russia require different tuning of the same stack.** China's GFW does passive ML/entropy classification + active probing + QUIC SNI inspection and kills "fully encrypted" and TLS-in-TLS protocols; Russia's TSPU does cruder but brutal protocol-signature blocking, IP-range/foreign-datacenter throttling (the "16 KB curtain"), and regional "whitelist" mobile shutdowns. REALITY's IP/connection-reputation exposure is the real risk in Russia, so plan for IP/port rotation and a clean, well-routed VPS.
- **For the repo, don't over-engineer step one.** Use a thin idempotent provisioner (Ansible, or a small Go/Python CLI you'll be proud of) that templates configs (Jinja2/Go templates), keeps secrets out of git (SOPS+age or Ansible Vault), and runs services via Docker Compose or systemd. Structure it so a future Terraform layer slots in cleanly above the config layer. Study `XTLS/Xray-examples`, `aleskxyz/reality-ezpz`, and `233boy/sing-box` as references.

## Key Findings

### The adversaries diverge — design for both

- **GFW (China)** is a multi-layered, increasingly ML-driven system. As of 2025-2026 its confirmed capabilities include: passive detection of fully-encrypted traffic via entropy/popcount and printable-ASCII heuristics (USENIX 2023); active probing of suspect servers (it replays/handshakes against your IP and blocks if it "looks like" a proxy); JA3/TLS fingerprinting; nationwide QUIC SNI inspection; DoH identification; and TCP RST injection. Per Zohaib et al., USENIX Security 2025 ("Exposing and Circumventing SNI-based QUIC Censorship of the Great Firewall of China"), QUIC blocking began **April 7, 2024**, and over the measurement period the GFW blocked **58,207 unique FQDNs** (averaging ~43.8K/week) via QUIC SNI inspection — a blocklist roughly 55% the size of its TLS-SNI list (102,216 domains) — and a single QUIC Initial packet can trigger blocking.

- **The September 2025 GFW leak was a watershed.** On **September 11, 2025**, hacktivist collective Enlace Hacktivista released nearly **600 GB** (including a 500 GB `repo.tar`), traced to **Geedge Networks** (chief scientist **Fang Binxing**, the "father of the GFW") and the CAS Institute of Information Engineering's **MESA Lab**, per GFW Report. It confirmed the **Tiangou Secure Gateway** — a turnkey "boxed GFW" — was exported to **Myanmar** (26 data centers, 81M concurrent TCP connections), **Pakistan** (WMS 2.0), **Ethiopia**, and **Kazakhstan**, and exposed the internal detection stack (JA3 fingerprinting, heuristic classifiers, statistical profiling).

- **GFW protocol "death dates" reported by the community (2025):** Trojan detection rose to ~90% in August 2025; VMess to ~80% in September 2025; plain Shadowsocks/obfs4 are flagged as fully-encrypted traffic. VLESS+REALITY+Vision remains the standout survivor. Treat specific percentages (e.g. "98% bypass") as community sentiment, not measured fact.

- **TSPU (Russia)** is cruder but escalating fast and better-funded. A Russian digital-development ministry proposal seen by **Reuters (Sept 2025)** earmarks nearly **60 billion rubles (~$660M) for TSPU over 2025–2030**, stating the aim to "increase the level of efficiency of restricting access to VPN blocking circumvention tools up to 96%." TSPU blocks VPN protocols by signature (OpenVPN, WireGuard, IKEv2, L2TP, PPTP), throttles rather than blocks (YouTube throttled to ~128 kbps), and in December 2025 updated TSPU signatures to target VLESS, SOCKS5, and L2TP. The "block VLESS" reports were nuanced — providers recovered by rotating configs.

- **Russia's real weapon against self-hosters is the "16-kilobyte curtain."** Per Cloudflare's official blog "Russian Internet users are unable to access the open Internet" (June 26, 2025): "A new tactic that began on June 9 limits the amount of content served to 16 KB, which renders many websites barely usable... The throttling affects all connection methods and protocols, including HTTP/1.1 and HTTP/2 on TCP and TLS, as well as HTTP/3 on QUIC." Named implementing ISPs: **Rostelecom, Megafon, Vimpelcom, MTS, MGTS.** The same throttle hit Hetzner, DigitalOcean, and OVH — the exact providers Russians use to host private VPNs. Technical analysis (net4people/bbs #490) shows the heuristic: a TLS 1.3 / HTTPS-pattern connection to a "suspicious" foreign datacenter IP gets frozen after ~25 packets (~16 KB). REALITY's crypto disguise is intact; what's targeted is destination IP reputation + connection volume.

- **Russia's "whitelist" mobile shutdowns are the worst case.** Per the Carnegie Endowment (Maria Kolomychenko, Dec 2025): "There are currently an average of 2,000 such shutdowns a month—more than in the rest of the world combined in 2024." A "whitelist" was first introduced **September 2025 as a "registry of socially significant services," initially comprising exactly 57 websites** (RIA Novosti, Gosuslugi, VK, the state messenger Max, Yandex services, Ozon, Wildberries, Avito), per Mediazona (zona.media, April 2026); Monitor Runet found it deployed in **57 of Russia's 80+ regions.** During whitelist mode almost no proxy works unless it routes through a whitelisted IP (e.g. a domestic relay).

### Protocol comparison (2026)

- **VLESS + XTLS-Vision + REALITY (Xray-core):** Best overall stealth. REALITY steals a real site's Server Hello, needs no domain/cert of your own, defeats SNI blocking and active probing (probes get forwarded to the real target). XTLS-Vision flattens TLS-in-TLS length/timing signatures and enables Linux `splice` for near-native throughput. Primary recommendation for both China and Russia.
- **Hysteria2 (QUIC/UDP):** Very fast on lossy/throttled links via "Brutal" congestion control (ignores loss). Salamander obfuscation + masquerade help, but UDP is "louder," and China throttles unclassified UDP (esp. China Telecom 163; QUIC SNI inspected since April 2024). Best as a speed-oriented fallback, not primary stealth. Note: active mid-connection bandwidth throttling cleanly separates Brutal from BBR (Brutal interprets the throttle as loss and pushes *harder*, an exploitable tell).
- **TUIC (QUIC/UDP):** Similar profile to Hysteria2; standard QUIC, occasionally throttled. Good fallback.
- **AmneziaWG (obfuscated WireGuard):** Randomizes WireGuard's fixed headers, adds junk/padding packets (Jc/Jmin/Jmax, H1–H4, S1–S4 params), can mimic QUIC/DNS. Kernel-module speed, same ChaCha20-Poly1305 crypto. Works in Russia where plain WireGuard is dead, but RKN periodically blocks its signatures (requiring updates) and it failed when Cloudflare/foreign IPs were throttled June 2025 (documented in amnezia-vpn/amnezia-client issue #1639). Excellent fallback, especially for full-tunnel/UDP. HRW (July 30, 2025) lists AmneziaWG among the ~7 protocols TSPU blocks.
- **Shadowsocks-2022 (AEAD, blake3):** Cleaner than legacy SS (proper PSK, replay protection, no active-probing TCP tell), but still "fully encrypted" traffic that GFW can flag; users report China IP bans within ~1 week. Some providers (WannaFlix) found SS still works well in China as of 2025 because some ISPs are more lenient to nondescript TCP/UDP than TLS. Mixed; not a first choice for max stealth. Use AEAD-2022 over TCP **with multiplexing** if used at all.
- **naiveproxy (Chromium/Caddy):** Uses Chrome's real network stack, defeats TLS fingerprinting and active probing via application fronting; survived large TLS-circumvention blocking waves in China. Strong but heavier to operate (Caddy+forwardproxy). Good alternative primary.
- **Trojan / Trojan-Go:** TLS-based, simple; GFW detection rose to ~90% in 2025. Declining.
- **Plain WireGuard / OpenVPN:** Dead in both China and Russia by DPI signature. Do not use without obfuscation.
- **Tor + bridges:** Fallback only. As of April 2025, China reports obfs4/meek/snowflake "unusable," and webtunnel connects but is quickly blocked. In Russia obfs4 still works on some ISPs; webtunnel on obscure hosts (not OVH/Hetzner/Linode/DO) helps. Not a primary path.

### Software stack: Xray-core vs sing-box vs v2ray

- **Xray-core** is the REALITY reference implementation, has the most mature XTLS-Vision/REALITY/XHTTP feature set (including current post-quantum mlkem768/mldsa65 options), a slightly better stealth toolbox, and (subjectively) better default performance. **Primary recommendation.**
- **sing-box** is a universal Go platform: one JSON config, TUN support, broad protocol support (Hysteria2, TUIC, ShadowTLS, naive), lower memory (~70 MB vs v2ray's 240+ MB), excellent client story. Best if you want one binary covering primary + all fallbacks. A reasonable alternative foundation; note the sing-box/Xray maintainer friction (sing-box independently reimplemented REALITY).
- **v2ray-core** is legacy; use Xray instead.
- **Verdict:** Xray-core for the REALITY primary; optionally sing-box for QUIC fallbacks (or run both). The repo should treat the core as a swappable component.

### Infrastructure / hosting

- **China:** Latency and packet loss matter as much as the protocol — China→international links can see 5–15% loss at peak, which cripples TCP-over-TCP. Premium China routes (CN2 GIA / CTGNet via China Telecom AS4809, CMIN2 AS58807 for Mobile, AS9929 for Unicom) dramatically reduce peak-hour loss. Locations: Hong Kong > Japan/Singapore/Korea > US West (LA) with CN2 GIA. Providers commonly cited: BandwagonHost (搬瓦工, ~$49.99/yr entry, CN2 GIA-E and free IP change every 2 weeks on higher tiers), DMIT (adds DDoS protection), LisaHost (native/residential dual-ISP IPs). Datacenter IPs from AWS/DO/GCP are flagged/blocked fastest; cleaner/"native"/residential IPs survive longer.
- **Russia:** Use a nearby clean-IP provider (Finland/Germany/Latvia). Hetzner is a technical gold standard but its ranges are now throttled/targeted by the 16 KB curtain and it rejects Russian payment; consider providers with cleaner ranges and Russian-friendly payment (Mir/SBP/crypto). Avoid the big foreign clouds whose ranges are throttled.
- **CDN/fronting:** Cloudflare in front (XHTTP+TLS over CDN) hides your origin IP and lets you rotate it, and "hides in the crowd" of Cloudflare traffic — but in Russia Cloudflare itself is throttled, so it cuts both ways. REALITY best practice: borrow a cert from the **same ASN / same country** as your VPS for plausibility and low latency; target must support TLS 1.3 + H2 and not be a redirect domain (a tool like `meower1/Reality-SNI-Finder` ranks candidate SNIs by TLS ping).
- **Port/camouflage:** 443 is natural for REALITY, but in Russia (Feb 2026, per Habr teardown) port 443 saw instant drops while high random ports (47000+) passed ~80% of packets, and **empty SNI lifted the block in 100% of cases** — so make port and SNI configurable knobs, not hardcoded.

### Operational security & resilience

- **Active-probing defense:** REALITY handles this inherently (probes are proxied to the real dest, which returns a legit cert and content). For SS/other protocols, a whitelist firewall (drop all inbound except your client IP, per net4people #246, the "Eye for an Eye" technique) dramatically prolongs server life.
- **Decoy/fallback:** Run a real nginx/Caddy site as the REALITY target ("steal from yourself") or front with nginx SNI routing so a browser hitting your IP sees a legit site. If your REALITY `dest` is behind a CDN, place nginx in front and filter unwanted SNIs so your box isn't abused as a port-forwarder/scanned.
- **Single-user advantage:** With one client you can lock the firewall to known client IPs/ranges, keep traffic volume low, and avoid the shared-IP traffic-analysis tell that plagues commercial VPNs.
- **Monitoring/recovery:** Watch for the failure signatures (handshake works then connection "freezes" after ~16 KB = Russia throttle; sudden RST = GFW). Recovery playbook: rotate port → rotate SNI / try empty SNI → rotate IP → switch transport (REALITY → AmneziaWG/Hysteria2) → switch provider/region. Keep a spare provisioned IP.

## Details

### Recommended primary architecture

1. **Core:** Xray-core, latest release, auto-updated monthly (keep current to match Chrome/uTLS fingerprints and new detection countermeasures).
2. **Primary inbound:** VLESS + TCP + REALITY + `flow: xtls-rprx-vision`, on 443 (with port configurable).
   - `dest`/`target`: a TLS 1.3 + H2 site in the **same ASN/region** as the VPS, not a redirect, ideally with a large certificate (≥3500 bytes) if enabling post-quantum mldsa65 padding.
   - Generate keys with `xray x25519`, UUID with `xray uuid`; use non-empty `shortIds`.
   - Consider mlkem768/mldsa65 post-quantum options now exposed in current Xray.
3. **Fallbacks (different ports / second core):**
   - **AmneziaWG** (kernel module) for a UDP full-tunnel option that survives Russian DPI when REALITY's IP gets throttled.
   - **Hysteria2** (sing-box) with Salamander obfuscation + masquerade for high-throughput on lossy links.
4. **Camouflage:** nginx/Caddy real site on the box; REALITY "steal-from-yourself" or steal-from-same-ASN. Optionally an XHTTP+TLS-over-Cloudflare inbound for an IP-rotation escape hatch (knowing Russia throttles CF). XHTTP additionally allows TLS 1.2 with an authentic nginx fingerprint and splits up/down connections to defeat TLS-in-TLS analysis.
5. **Hardening:** UFW/nftables default-deny; for non-REALITY protocols, client-IP whitelist; fail2ban; disable outbound SMTP (25/465/587); BBR enabled.

### Why this beats the alternatives

REALITY uniquely removes the two things that kill everything else: it has **no distinct VPN handshake** (it is a real TLS 1.3 handshake to a real site) and **no self-signed cert/SNI to block** (it borrows a real one). XTLS-Vision removes the TLS-in-TLS length/timing tell that dooms naive TLS tunnels and naiveproxy-style stacks under ML classifiers ("nobody does 3-way handshakes twice in a row"). The fallbacks cover REALITY's two weaknesses: TCP-over-TCP throughput collapse on lossy links (→ Hysteria2/TUIC QUIC) and IP/volume-reputation throttling in Russia (→ AmneziaWG on random UDP ports, or IP rotation behind a CDN).

### Reference repos worth studying

- **`XTLS/Xray-examples`** — canonical REALITY/XHTTP server+client JSON; the source of truth for config shape (incl. a "without being stolen" dokodemo-door variant that blocks unauthorized SNIs).
- **`aleskxyz/reality-ezpz`** — Docker Compose installer supporting Xray *and* sing-box, multiple transports (tcp/http/grpc/ws/tuic/hysteria2/shadowtls), reality/letsencrypt/selfsigned, user management via CLI/TUI/Telegram. Excellent architecture reference for multi-protocol + fallback on one box.
- **`233boy/sing-box`** (and `233boy/v2ray`) — battle-tested one-command installers with clean management CLIs (`sb add reality`, etc.); good UX patterns and a tidy state model.
- **`amnezia-vpn/amneziawg-go`** + community `amneziawg-installer` — AWG params and state-machine installers that survive reboots/DKMS.
- **`klzgrad/naiveproxy`** — if you choose the Chromium-stack route.

### Repo architecture for a principal engineer

**Goal:** idempotent, reproducible, secrets-safe, swappable core, extensible toward Terraform — without IaC bloat in step one.

Recommended layout:
```
repo/
  README.md
  Makefile                      # one-word entrypoints: make deploy / rotate / status
  ansible/                      # or cmd/ if you write a Go provisioner
    inventory/                  # hosts.yml (gitignored real values) + example
    playbooks/site.yml
    roles/
      base/                     # OS hardening, BBR, ufw/nftables, fail2ban
      xray/                     # install, template config, systemd unit
      amneziawg/                # kernel module, params, wg config
      hysteria2/                # sing-box install + config
      decoy_site/               # nginx/caddy cover site
  config/
    templates/                  # *.json.j2 / *.conf.j2 (Jinja2 or Go text/template)
  secrets/
    secrets.sops.yaml           # SOPS+age encrypted; UUIDs, keys, PSKs
  compose/                      # docker-compose.yml if container route
  scripts/                      # rotate-ip.sh, healthcheck.sh, blocked-check.sh
  docs/
    threat-model.md  runbook.md  decisions/ (ADRs)
```

**Engineering choices:**

- **Provisioner:** Ansible is the pragmatic pick — agentless over SSH, idempotent, mature templating, easy secrets via Vault, and the natural layer *below* a future Terraform. Pure bash gets messy and non-idempotent (a failure mid-run leaves a half-configured box). Nix is reproducible but overkill for one box and a steep yak-shave. Given Python/Go fluency, a small **Go CLI using `text/template` + an SSH library** is a legitimate, elegant alternative you'll enjoy maintaining and that compiles to a single static binary — but write it as a thin wrapper, not a full config-management reinvention. Recommendation: **Ansible for step one; keep the door open to a Go CLI if you want ownership of the tooling.**
- **Containers vs systemd:** Docker Compose gives clean version pinning, reproducible runtime, and easy multi-protocol composition (this is what reality-ezpz does). systemd units are lighter and avoid Docker's UDP/network quirks (relevant for QUIC/WireGuard). Recommendation: **systemd for AmneziaWG (kernel module) and Xray; Compose optionally for the decoy site + sing-box.** Make it a per-role choice.
- **Secrets:** Never commit UUIDs/keys/PSKs. Use **SOPS + age** (great Git-native diff/rotation, language-agnostic) or **Ansible Vault**. Provide a `secrets.example`. Generate secrets on first run; store encrypted.
- **Config as templates:** Single source of truth for variables (port, SNI/dest, UUID, key) → templated into Xray JSON, wg conf, hysteria yaml. One variable change propagates everywhere (the core reason to template rather than hand-edit — e.g. changing the listening port should be one edit, not six).
- **Idempotency & reproducibility:** Pin Xray/sing-box/AWG versions in vars; checksum-verify downloads; make every task safe to re-run. A `make deploy` should converge a fresh VPS to a working state unattended.
- **Extensibility toward Terraform:** Keep "provision the box" (Terraform's future job: create VPS, DNS, firewall) cleanly separated from "configure the box" (Ansible/your CLI today). Have Ansible read host data from an inventory that Terraform can later generate (e.g. via the `terraform` inventory plugin or a generated `hosts.yml`). Use ADRs (`docs/decisions/`) to record the cat-and-mouse changes over time — this domain *will* churn.
- **Resilience tooling:** `scripts/blocked-check.sh` (probe from an external vantage / test handshake + >16 KB transfer to detect the Russian freeze), `rotate-ip.sh`, and a health endpoint. A single `make rotate` to cycle port/SNI/IP is the highest-value operational feature.

## Recommendations

**Stage 0 — MVP (this week):**

- Provision one clean-IP VPS (China target: HK/JP/Korea with CN2 GIA-class routing; Russia target: Finland/Germany with a clean, non-Hetzner-flagged range).
- Deploy Xray VLESS+Vision+REALITY/443 with a same-ASN `dest`, behind a real decoy site. Lock firewall default-deny.
- Get it into the repo as an idempotent Ansible role + SOPS secrets + templated config. `make deploy` must be repeatable on a fresh box.

**Stage 1 — Resilience:**

- Add AmneziaWG (systemd, kernel module) on a random high UDP port as fallback. Add Hysteria2 (sing-box) with Salamander + masquerade for throughput.
- Implement `make rotate` (port/SNI/IP) and `blocked-check.sh`. Provision a spare standby IP.

**Stage 2 — Hardening & extensibility:**

- Add an XHTTP+TLS-over-Cloudflare inbound as an IP-rotation escape hatch (China-leaning; remember CF is throttled in Russia).
- Add ADRs, a runbook, and monitoring. Keep config/provision separation clean so Terraform can later own VPS/DNS/firewall creation.

**Benchmarks/triggers that should change your plan:**

- If REALITY/443 starts dropping in Russia → move to high random port (47000+), try empty SNI, then rotate IP, then switch to AmneziaWG.
- If your IP is blackholed in China shortly after heavy use → you're being actively probed/volume-flagged; rotate IP, reduce footprint, verify REALITY dest quality, confirm CN2 routing.
- If QUIC/UDP is throttled (China Telecom peak hours) → switch carrier route or fall back to REALITY TCP.
- If whitelist mode hits (Russia regional shutdown) → only a domestic-whitelisted relay hop will help; accept degraded service.

## Caveats

- **This is a fast-moving cat-and-mouse domain.** Specific detection percentages and "death dates" (Trojan ~90% Aug 2025, VMess ~80% Sept 2025, "98% REALITY bypass") come largely from community blogs/forums and promotional sites; treat them as directional, not measured. The high-confidence facts are the academic GFW Report/USENIX papers, the Cloudflare throttling blog, net4people/bbs technical threads, HRW/Carnegie/Mediazona reporting, and the official Xray/Amnezia docs.
- **Legal risk is real and rising.** China's MSS issued a November 2025 warning on circumvention; a cybercrime law and "making an example" cases are increasing. Russia has criminalized VPN advertising (Sept 2025) and fines searching for "extremist" content via VPN, with proposals to go further (including reported March 2026 pressure on tech firms to detect VPN-connecting users). This report is about technical architecture, not legal advice.
- **No single protocol is permanently safe.** The whole point of the multi-protocol + rotation design is that any one transport can fall; resilience comes from the operational playbook, clean IPs, and the ability to switch fast — not from betting everything on REALITY.
- **Russia's IP/volume throttle (16 KB curtain) targets infrastructure, not just protocols** — so provider/IP/ASN choice matters as much as protocol choice there, and the best mitigation is clean IPs + rotation, possibly a domestic relay hop for whitelist periods. The "VLESS block," the Cloudflare throttle, and AmneziaWG-over-Cloudflare failures are best understood as one underlying TSPU mechanism: freeze TLS-1.3/HTTPS-pattern connections to non-whitelisted foreign datacenter IPs once they exceed ~16 KB.