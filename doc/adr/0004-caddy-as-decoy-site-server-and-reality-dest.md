# 4. Caddy as the Decoy Site Server and REALITY Destination

Date: 2025-07-14

## Status

Proposed

## Context

FEAT-0005 introduces a decoy cover site to eliminate the VPS's passive fingerprint: after `make deploy`, a bare Xray server that listens only on one high port with no HTTP identity is more conspicuous than running no server at all. REALITY's transparent forwarding requires an explicit `dest` in the Xray config — probes that arrive without valid REALITY magic bytes are forwarded to that destination, and the probe receives that destination's TLS certificate and content.

Two modes must be supported:

1. **No domain:** the operator has not pointed a real domain at the VPS. REALITY `dest` must be an external TLS 1.3 site (e.g., `microsoft.com:443`). A local HTTP-only cover page on port 80 still improves the passive fingerprint.
2. **With domain:** the operator controls a domain with an A record pointing to the VPS IP. A locally-hosted TLS site on port 443 lets `dest` be `127.0.0.1:443`, so active probes receive the VPS's own valid Let's Encrypt certificate — indistinguishable from a real site at any external vantage point.

A new variable `xray_reality_dest` is introduced to `vars/main.yml` (addendum to the schema contract established in TASK-0001). The Xray config template (TASK-0004) must reference `xray_reality_dest` rather than deriving it from `xray_server_name`. This variable is the interface contract between the `decoy_site` role and the `xray` role; any future feature that changes how REALITY probes are handled must go through this variable.

The web server choice determines: whether ACME certificate issuance is built-in or requires an external agent, what the systemd service name is (referenced in firewall and Molecule assertions), and whether the role has dependencies beyond what APT provides.

## Decision

We adopt **Caddy** (installed from the official Caddy APT repository, pinned major version) as the decoy site web server for the `decoy_site` Ansible role introduced in FEAT-0005.

Caddy is configured via a single `Caddyfile` rendered by an Ansible template. Two rendering paths exist, controlled by the `decoy_domain` variable:

- `decoy_domain` empty: Caddy serves plain HTTP on port 80 only. No TLS, no ACME. `xray_reality_dest` defaults to `"{{ xray_server_name }}:443"` (external site).
- `decoy_domain` set: Caddy obtains a Let's Encrypt ACME certificate automatically via HTTP-01 challenge and serves HTTPS on port 443 with HTTP redirect on port 80. `xray_reality_dest` is set to `"127.0.0.1:443"`.

Caddy is managed as a systemd service (`caddy.service`), enabled at boot. The `decoy_site` role runs last in `playbook.yml`, after the `firewall` role, so that port 80 is open before the ACME HTTP-01 challenge is attempted.

The cover page is a single static `index.html`; title and body text are configurable via `decoy_site_title` (default: `"Software Solutions"`).

**Alternatives rejected:**

- **nginx:** nginx is the most common choice and is available in base APT repositories, but it has no built-in ACME client. Achieving ACME certificate issuance requires either `certbot` (a second package and a cron job or systemd timer) or `acme.sh` (a shell script dependency). This adds two new dependencies, two new systemd units to manage, and a non-trivial renewal lifecycle to make idempotent in Ansible. Caddy handles issuance and renewal internally with no additional packages. For a use case where the primary value of TLS is a valid probe response (not long-term certificate management), Caddy's built-in ACME eliminates a class of operational failure.

- **Apache httpd:** Same objection as nginx regarding ACME. Additionally, Apache's config model (virtual hosts, `.htaccess`, modules) is significantly more complex than a Caddyfile for the single-static-page use case. Molecule assertions would need to introspect more files and service states.

- **Python `http.server` / static-only solution:** A minimal HTTP server (e.g., a Python one-liner managed as a systemd service) could serve the plain HTTP case but has no TLS story at all. This forecloses the `127.0.0.1:443` REALITY dest mode, which is the primary fingerprint-resistance benefit of the decoy site. Ruled out because it cannot satisfy the `decoy_domain`-with-ACME requirement without adding a separate TLS termination layer.

- **External real site as permanent dest (no local server):** Using a real external TLS site (e.g., `microsoft.com:443`) as `xray_reality_dest` permanently avoids the need for a local web server. This is valid for the no-domain case and is the default. However, it means active probes receive a certificate for a domain the VPS IP is not authoritative for — a sophisticated prober querying DNS and comparing can detect the mismatch. The local Caddy + ACME approach eliminates this gap when the operator controls a domain. Both modes are supported; the local server is not forced on operators without a domain.

**Reversibility:** Moderate. The Caddy APT repository is a new external dependency. If Caddy's APT repository becomes unavailable or the project changes licensing, the `decoy_site` role must be updated to use an alternative installation method (binary download with checksum, package mirror). The `xray_reality_dest` variable contract is the stable interface; the underlying server implementation is replaceable without touching the `xray` role, provided the new server can listen on port 443 with a valid TLS certificate. The decision is **moderately reversible**: replacing Caddy requires rewriting the role but does not affect the `xray` role or the `vars/main.yml` schema.

## Consequences

- **Positive:** Caddy's built-in ACME client reduces the `decoy_site` role to a single package, a single Caddyfile template, and a single systemd service — no certbot, no renewal cron, no second service to manage or assert in Molecule.
- **Positive:** The `xray_reality_dest` variable cleanly decouples the `xray` role from the `decoy_site` role. The Xray config template references `xray_reality_dest` without knowing whether the destination is local or external.
- **Positive:** When `decoy_domain` is set, active REALITY probes receive a certificate that is genuinely authoritative for the VPS IP and the configured domain — not a certificate for a third-party domain. This is the strongest available fingerprint resistance for the probe response.
- **Negative:** The Caddy APT repository (`deb.cadeserver.io`) is an external dependency not present in base Ubuntu/Debian APT sources. The prerequisites role must add the repository and its GPG key. This adds a new failure mode (repository unreachable at provision time) and a new maintenance burden (key rotation). The Caddy version must be pinned and the checksum documented.
- **Negative:** Let's Encrypt enforces 5 certificate requests per registered domain per week. Repeated `make deploy` runs against fresh VPSes on the same `decoy_domain` will exhaust this limit. Operators must use the Let's Encrypt staging environment for testing. Idempotency (Caddy does not re-request a valid cert) mitigates this for re-runs on the same VPS, but the rate limit is a hard constraint for multi-VPS testing workflows.
- **Negative:** Caddy download and startup adds approximately 30 seconds to cold `make deploy` time. This must be profiled against FEAT-0001's AC-2 (cold deploy ≤15 minutes). If the limit is threatened, Caddy installation must be pre-downloaded or cached.
- **Schema impact:** The `xray_reality_dest` variable is a breaking addition to the `vars/main.yml` schema defined in TASK-0001. Any implementation of the Xray role (TASK-0004) that hardcodes `xray_server_name` as the REALITY dest must be updated before FEAT-0005 can be merged.
- **Firewall impact:** The firewall role (TASK-0006) must open port 80 unconditionally when `decoy_site` is in the role list, and port 443 when `decoy_domain` is set. A `decoy_enabled` variable gates inclusion of the role; when false, neither port is opened.
