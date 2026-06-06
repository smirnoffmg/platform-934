---
id: SOL-0008
status: proposed
problem_hypothesis_id: PROB-0001
target_metric_id: MET-0008
secondary_metric_ids:
  - MET-0003
---
# REALITY Transparent Forwarding and Client-IP Firewall Whitelist for Active-Probe Resistance

## Context

Active probing is primarily a GFW mechanism: after passive classifiers flag a suspicious connection, the GFW replays the captured TLS ClientHello against the server from multiple vantage points. If the server responds differently from a real TLS site — with a self-signed cert, a connection reset, or unexpected content — the IP is blocked. Most "looks-like-HTTPS" proxies fail this test within hours of first use.

TSPU does not document active probing to the same degree, but the client-IP firewall whitelist provides defense in depth against any scan-based detection, including TSPU port scans that could identify an open proxy.

Two complementary defenses are available:

**REALITY transparent forwarding:** When any probe arrives at the REALITY port, Xray-core splices the connection to the configured `dest` site and returns the real site's TLS Server Hello, certificate, and content. The server is literally indistinguishable from the destination site to an external observer — because it is forwarding to the real destination.

**Client-IP firewall whitelist:** UFW or nftables default-deny inbound, with only the known client IP(s) whitelisted on the proxy port. Any probe from an unrecognized source IP — GFW scanners, TSPU scanners, public port scanners — is silently dropped before reaching the Xray process at all. This eliminates the probe attack surface for all protocols on the server, not just REALITY.

## Decision

We hypothesize that combining REALITY's transparent forwarding (with `dest` configured to a real TLS 1.3 + HTTP/2 site in the same ASN as the VPS) with a default-deny firewall that whitelists only the client IP will result in:

1. 100% of GFW-style probe replays receiving a valid TLS response indistinguishable from the real destination site.
2. The server IP remaining unblocked for ≥72 h post-deployment.
3. All non-whitelisted connection attempts being silently dropped.

## Experiments

1. **Probe-replay validity:** Run a GFW-style probe-replay script (mimicking USENIX Security 2023 documented patterns: replayed TLS ClientHellos and raw TCP payloads) against the deployed server from a neutral vantage. Confirm all probes receive a valid TLS response matching the `dest` site.

2. **72 h China vantage reachability:** Poll the server from a China-routed vantage every 6 h for 72 h. Confirm the IP remains reachable.

3. **Firewall whitelist validation:** From a non-whitelisted IP, attempt TCP connection on the proxy port. Confirm: no RST (which would confirm an open port to a scanner), no response — silent drop only.

4. **dest site selection impact:** Test two `dest` configurations: same-ASN site vs. geographically distant CDN-backed site. Compare probe response quality and survival duration. Confirm same-ASN `dest` produces lower-latency, more convincing probe responses.

5. **Whitelist bypass test:** Confirm that spoofed source IP packets (from a non-whitelisted IP with a spoofed whitelisted source) are handled correctly — the TCP handshake requires real source routing, so spoofing should not bypass the whitelist.

## Success criteria

- MET-0008: Probe-replay script receives valid TLS response (not RST) on 100% of probe attempts; server IP remains reachable from China-routed vantage for ≥72 h.
- Non-whitelisted connection attempts: 100% silently dropped (zero RSTs, zero responses).
- Same-ASN `dest` produces probe response latency within 20 ms of direct connection to the `dest` site.

## Consequences

- **If confirmed:** REALITY transparent forwarding with same-ASN `dest` and client-IP whitelist becomes the mandatory configuration. Self-signed-cert or non-TLS-1.3 `dest` configurations are explicitly prohibited.
- **If probe responses are distinguishable:** The `dest` site selection criteria need tightening — likely the site uses TLS 1.2, has a redirect chain, or the cert properties don't match. The serverName curation list (MET-0003) becomes the primary corrective lever.
- **If 72 h survival fails despite valid probe responses:** The block is driven by traffic volume or IP reputation rather than active probing — the curtain or reputation mechanism, not the handshake.
- **Ongoing risk:** If the `dest` site is itself blocked or goes offline, REALITY's probe responses degrade. The provisioner should verify `dest` reachability as part of post-deploy checks.
