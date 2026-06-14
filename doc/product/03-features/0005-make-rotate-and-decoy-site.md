---
id: FEAT-0005
status: accepted
solution_hypothesis_id: SOL-0005
architectural_review_status: cleared
---

# Single-Command Rotation and Decoy Cover Site

## Context

Two operational gaps remain after FEAT-0001 through FEAT-0004 deliver a working `make deploy` pipeline.

**Rotation gap (SOL-0005):** SOL-0005's hypothesis — that port+SNI rotation should complete in ≤5 minutes — has no implementation path. FEAT-0001 establishes that all protocol parameters are Ansible variables and that re-running the playbook is idempotent, making fast rotation structurally possible. But no Makefile target, port-picker script, or SNI candidate list exists. Without `make rotate`, the operator must manually edit `vars/main.yml`, figure out which variables to change, re-run `ansible-playbook`, and run `make check` — a sequence that takes 10–20 minutes of focused attention and is error-prone under censorship pressure. At that friction level, operators tolerate a burned config for days rather than rotate.

**Cover identity gap (SOL-0008):** After `make deploy`, the VPS has no HTTP identity. Any connection to port 80 is refused; any passive observer who discovers the VPS IP sees a server that listens on one unusual high port and nothing else. This is a stronger fingerprint than running no server at all. SOL-0008 calls for REALITY's transparent forwarding — probes that arrive without valid REALITY magic bytes are forwarded to a real TLS 1.3 destination and receive that destination's certificate and content. The `dest` for that forwarding must be declared explicitly in the Xray config. A locally-hosted Caddy cover site with an ACME certificate enables the `dest` to be `127.0.0.1:443`, producing a probe response that is literally the VPS's own valid TLS certificate and content — indistinguishable from the real site at any external vantage point.

These two concerns are bundled here because changing `xray_server_name` (what `make rotate` does) and changing the REALITY `dest` (what the decoy site determines) are coupled: a valid `serverName` must correspond to a reachable TLS endpoint, and the decoy site with ACME is the mechanism that makes the VPS itself a valid TLS endpoint for that name.

## Decision

**In scope:**

**Part A — `make rotate` target:**

- A `make rotate` Makefile target that executes in sequence: (1) runs `scripts/new-port.sh` to generate a random unused port in range 47001–65535 and writes it to `xray_port` in `vars/main.yml`; (2) optionally selects a new `xray_server_name` from `config/sni-candidates.txt` (one domain per line, operator-curated); (3) re-runs `ansible-playbook` against the existing VPS — idempotent, so only Xray and firewall tasks report `changed`; (4) runs `make check` (FEAT-0003); (5) prints the new `xray_port` and `xray_server_name` to stdout on success so the operator can update client configs.
- `scripts/new-port.sh`: selects a random integer in 47001–65535, verifies it is not in the current `vars/main.yml` port set and not reported as in use by `ss -ltn` on the local workstation (the VPS port check is confirmed by attempting the bind via Ansible), and outputs the selected port.
- `config/sni-candidates.txt`: a plain text file in the repository, one FQDN per line, listing real TLS 1.3 + HTTP/2 domains suitable for use as REALITY `serverName`. Operator-maintained. `make rotate` picks a random entry. Override with `SNI=<value>` make variable to set a specific SNI without editing the file.
- `ROTATE_SECRETS=1 make rotate` additionally runs `make secrets` (FEAT-0002) before the playbook to regenerate the Xray UUID and x25519 keypair. Default: port+SNI rotation only, existing secrets untouched.
- On connectivity check failure: `make rotate` exits non-zero, prints both the old and new port values to stderr so the operator can diagnose. Does not revert `vars/main.yml` automatically — the operator may re-run `make rotate` or manually restore the previous port and re-deploy.
- A `make rotate` run must not restart AmneziaWG or Hysteria2 (Ansible idempotency ensures this if only Xray-variable-dependent tasks report `changed`). Verified by capturing Ansible output and asserting AmneziaWG and Hysteria2 handler names do not appear in the `changed` task list.

**Part B — `decoy_site` Ansible role:**

- `roles/decoy_site/` role that installs Caddy and serves a minimal static HTML page.
- Caddy is configured with two behaviours depending on the `decoy_domain` variable:
  - If `decoy_domain` is set (a real domain with an A record pointing to the VPS IP): Caddy obtains a Let's Encrypt ACME certificate automatically and serves HTTPS on port 443 and HTTP redirect on port 80. The REALITY `dest` (`xray_reality_dest` variable, see below) should be set to `127.0.0.1:443` to forward active probes to the local Caddy instance.
  - If `decoy_domain` is empty: Caddy serves plain HTTP on port 80 only, no TLS. `xray_reality_dest` must be an external real TLS domain in this case.
- Cover page content: a minimal plausible static HTML page (title and text configurable via `decoy_site_title` variable, default: `"Software Solutions"`). Not a WordPress site; a single `index.html`.
- Caddy is managed as a systemd service, enabled at boot.
- Role execution order: `decoy_site` runs last in `playbook.yml`, after `firewall`, because the firewall must open port 80 before the ACME HTTP-01 challenge can complete.
- Firewall role (TASK-0006) must be updated to open port 80 unconditionally when `decoy_site` is in the role list, and port 443 when `decoy_domain` is set.
- A new variable `xray_reality_dest` is added to `vars/main.yml` (addendum to TASK-0001). Default: `"{{ xray_server_name }}:443"` (external real site). Operators who configure `decoy_domain` set it to `"127.0.0.1:443"`. The Xray config template in TASK-0004 must reference `xray_reality_dest` rather than a hardcoded external dest.
- A Molecule scenario (Docker driver) verifies: Caddy installed and `systemctl is-active caddy` returns 0, port 80 serves HTTP 200, response body contains `decoy_site_title`. ACME cert issuance is not tested in Molecule (requires real public domain and Let's Encrypt reachability).

**Out of scope:**

- Full IP rotation (new VPS provisioning). Rotating to a new VPS requires cloud provider API integration (VM create, DNS update). This is a follow-up feature.
- Automated rotation on a schedule or on burn-detection trigger. `make rotate` is operator-initiated only.
- Client config file generation. `make rotate` outputs the new parameters to stdout; the operator updates client devices manually. Client config generation is a future feature.
- Dynamic or database-backed decoy sites. A single static `index.html` is the entire scope.
- WordPress, reverse-proxy decoy sites, or any decoy that requires outbound connectivity from the decoy site itself.
- ACME cert issuance in CI / Molecule. The Molecule scenario uses HTTP-only and does not attempt ACME.
- Multi-SNI rotation or automatic SNI discovery. The operator maintains `config/sni-candidates.txt` manually.

## Testing

| AC                                      | Molecule/Docker                       | Real VPS required | Notes                         |
| --------------------------------------- | ------------------------------------- | ----------------- | ----------------------------- |
| AC-3 (port updates vars/main.yml)       | ✓ shell test                          |                   |                               |
| AC-4 (only Xray+firewall change)        | ✓ Molecule idempotency on role subset |                   |                               |
| AC-5 (stdout contains new port+SNI)     | ✓ shell test                          |                   |                               |
| AC-6 (exit non-zero on check failure)   | ✓ mock make check                     |                   |                               |
| AC-10 (decoy HTTP 200)                  | ✓ Molecule verify                     |                   | HTTP-only in Docker           |
| AC-11 (decoy idempotency)               | ✓ Molecule idempotency check          |                   |                               |
| AC-12 (HTTP-only when no domain)        | ✓ Molecule (decoy_domain: "")         |                   |                               |
| AC-1 (rotation ≤5 min)                  | —                                     | ✓                 | Timing not reliable in Docker |
| AC-2 (old port no longer listening)     | —                                     | ✓                 | Requires real bound port      |
| AC-3 (make check passes on new port)    | —                                     | ✓                 | Requires real tunnel          |
| AC-8 (ACME cert, HTTPS on decoy_domain) | —                                     | ✓                 | Requires real domain + ACME   |
| AC-9 (REALITY dest = local Caddy)       | —                                     | ✓                 | Requires real Xray process    |

## Acceptance criteria

- **AC-1 (Rotation time):** Wall-clock time from `make rotate` invocation to `make check` passing is ≤5 minutes at the median across 5 consecutive runs on a live server with an established baseline config.
- **AC-2 (Old port closed):** After `make rotate` exits 0, `ss -ltn` on the VPS shows no listener on the previous port. The previous port is unreachable from the controller within 10 seconds of `make rotate` completing.
- **AC-3 (New port reachable):** `make check` (FEAT-0003) passes on the new port immediately after `make rotate` exits 0.
- **AC-4 (Minimal blast radius):** During `make rotate`, only Xray and firewall Ansible tasks appear in the `changed` summary. AmneziaWG and Hysteria2 handler names do not appear. Verified by capturing `ansible-playbook` stdout and asserting the absence of `Restart amneziawg` and `Restart hysteria2`.
- **AC-5 (Operator output):** On success, `make rotate` prints to stdout at minimum: `New port: <port>` and `New SNI: <sni>` so the operator has all information needed to update client configs without opening `vars/main.yml`.
- **AC-6 (Failure handling):** If `make check` fails after the playbook run, `make rotate` exits non-zero and prints to stderr both the old port (for rollback reference) and the new port (for diagnosis). `vars/main.yml` retains the new values (not auto-reverted) so the operator can debug or re-run.
- **AC-7 (SNI override):** `SNI=example.com make rotate` sets `xray_server_name: "example.com"` in `vars/main.yml` without prompting and without reading `config/sni-candidates.txt`. The file need not be present.
- **AC-8 (Decoy HTTP):** After `make deploy`, `curl -s -o /dev/null -w "%{http_code}" http://<VPS-IP>` returns `200`. The response body contains the configured `decoy_site_title`.
- **AC-9 (Decoy HTTPS with domain):** When `decoy_domain` is set to a real domain with a valid A record, after `make deploy`, `curl -s https://<decoy_domain>` returns HTTP 200 with a valid TLS certificate issued by Let's Encrypt for `decoy_domain`. (Real VPS only; not tested in Molecule.)
- **AC-10 (Decoy Molecule):** The `decoy_site` Molecule scenario (Docker, HTTP-only mode) exits 0. It verifies: `caddy` binary present, `systemctl is-active caddy` exits 0, `curl localhost:80` returns 200, response body contains `decoy_site_title`.
- **AC-11 (Decoy idempotency):** Running `make deploy` a second time on a VPS with the decoy site active produces `changed=0` for the `decoy_site` role.
- **AC-12 (HTTP-only fallback):** When `decoy_domain` is empty, Caddy serves only port 80. No HTTPS listener is started. `vars/main.yml` retains `xray_reality_dest: "{{ xray_server_name }}:443"` pointing to an external site.

## Consequences

- **`xray_reality_dest` is a breaking schema addition:** The xray role template (TASK-0004) currently has no `xray_reality_dest` variable — it uses `xray_server_name` implicitly. Adding `xray_reality_dest` to `vars/main.yml` is an addendum to TASK-0001's schema contract; any implementation of TASK-0004 already in progress must be updated to reference the new variable. This must be resolved before FEAT-0005 can be merged.
- **Port 80 is now open:** The firewall role (TASK-0006) currently opens only SSH, Xray, Hysteria2, and AmneziaWG ports. Adding port 80 for the decoy site changes the firewall posture. Operators who do not want an HTTP listener can set `decoy_enabled: false` (a new variable) to skip the role; the firewall rule for port 80 must be conditional on this variable.
- **`make rotate` modifies `vars/main.yml` in place:** After a successful rotation, the vars file differs from the last commit. The operator must commit the change (`git add ansible/vars/main.yml && git commit -m "rotate: port X → Y, SNI A → B"`) to keep the repository state consistent. This is not automated. Document clearly that an uncommitted rotation leaves the repo in a state where `git stash` or `git checkout` would revert to the pre-rotation config.
- **`config/sni-candidates.txt` is operator-maintained:** If the list is empty or all listed domains are blocked at the destination, `make rotate` must fail with `ERROR: sni-candidates.txt is empty or no valid entry selected` rather than proceeding with an empty or invalid SNI. The failure must be loud.
- **Caddy ACME rate limits:** Let's Encrypt enforces 5 certificate requests per registered domain per week. Repeated `make deploy` runs against a fresh VPS on the same `decoy_domain` will exhaust this limit quickly. Operators must be aware that `make deploy` on an already-certified server is idempotent (Caddy does not re-request a valid cert), but provisioning multiple fresh VPSes with the same domain in a week will be rate-limited. Use Let's Encrypt staging environment for testing.
- **Rotation does not update client configs:** `make rotate` outputs the new parameters to stdout but does not write, push, or transmit a new client config file to any device. The operator is responsible for updating all client configurations manually after each rotation. This is a known usability gap; client config generation is deferred to a future feature.
- **Decoy adds ~30 s to cold deploy:** Caddy download and startup adds time to `make deploy`. This must be profiled to confirm FEAT-0001's AC-2 (cold deploy ≤15 min) is not violated. If it is, Caddy installation must be optimized (pre-downloaded binary, pinned version checksum).
