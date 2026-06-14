---
id: TASK-0013
status: todo
feature_id: FEAT-0005
---

## Description

`roles/decoy_site/` is an idempotent Ansible role that installs Caddy, writes a minimal static HTML cover page, and manages a Caddy systemd service. When `decoy_domain` is set, Caddy obtains a Let's Encrypt ACME certificate and serves HTTPS on 443 with HTTP redirect on 80. When `decoy_domain` is empty, Caddy serves plain HTTP on port 80 only. After this task, any connection to the VPS on port 80 receives a plausible HTTP 200 response, eliminating the "listens on one unusual high port" fingerprint.

Done looks like:

- `roles/decoy_site/tasks/main.yml` installs the Caddy binary (pinned version, checksum verified), writes `/etc/caddy/Caddyfile` from a Jinja2 template, installs `/var/www/decoy/index.html` from a template, enables and starts the `caddy` systemd service.
- `roles/decoy_site/templates/Caddyfile.j2` has two branches:
  - If `decoy_domain` is non-empty: configures Caddy to serve `https://{{ decoy_domain }}` with automatic ACME TLS and an HTTP→HTTPS redirect for port 80.
  - If `decoy_domain` is empty: configures Caddy to serve `http://:80` only, no TLS block.
- `roles/decoy_site/templates/index.html.j2` renders a minimal single-page HTML document whose `<title>` and visible heading contain `{{ decoy_site_title }}` (default: `"Software Solutions"`).
- `vars/main.yml` (via TASK-0009) already declares `decoy_domain: ""`, `decoy_enabled: false`, and `decoy_site_title: "Software Solutions"` with inline comments.
- Re-running with no variable changes produces `changed=0` for the role.
- Role is skipped entirely when `decoy_enabled: false` via a `when: decoy_enabled` condition on all tasks (or via `roles:` conditional in `playbook.yml`).

## Notes

- Depends on TASK-0009 (vars schema declares `decoy_domain`, `decoy_enabled`, `decoy_site_title`). Must be developed after those variables are merged.
- Depends on TASK-0014 (firewall opens port 80/443 for Caddy) being applied in the same playbook run; the ACME HTTP-01 challenge requires port 80 to be reachable before Caddy can complete cert issuance. Role ordering in `playbook.yml` enforces this: `firewall` runs before `decoy_site`.
- Pin the Caddy version (e.g., from the official GitHub releases) and verify the binary checksum. Document the version and the update procedure in `roles/decoy_site/README.md`.
- The `index.html` must be a plausible but generic page — no obvious proxy-tool language, no Lorem Ipsum. The default title "Software Solutions" satisfies this.
- ACME cert issuance is not testable in Docker/Molecule. The Molecule scenario (TASK-0015) uses HTTP-only mode (`decoy_domain: ""`). Document the ACME path as real-VPS only.
- Caddy's idempotency: Caddy does not re-request a valid cert on restart; the ACME state is stored in `/var/lib/caddy/.local/share/caddy/`. Ensure this directory is not cleaned between Ansible runs.
- Warn operators in `roles/decoy_site/README.md` about Let's Encrypt rate limits (5 cert requests per registered domain per week) and recommend the staging ACME endpoint for testing.
