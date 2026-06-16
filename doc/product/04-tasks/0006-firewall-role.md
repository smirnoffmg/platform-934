---
id: TASK-0006
status: todo
feature_id: FEAT-0001
---

## Description

An idempotent `firewall` Ansible role applies an nftables (or ufw) ruleset that enforces default-deny inbound with explicit allowances for SSH, the configured Xray port, the configured Hysteria2 port, and the configured AmneziaWG port, and restricts SSH access to IPs in `client_ip_whitelist`. After this task, `nft list ruleset` on the VPS matches the expected policy and a re-run produces `changed=0`.

Done looks like:

- `roles/firewall/templates/nftables.conf.j2` (or equivalent ufw task sequence) generates rules driven entirely by variables from `vars/main.yml`: `ssh_port`, `xray_port`, `hysteria2_port`, `awg_port`, and `client_ip_whitelist`.
- The rendered ruleset: sets default policy to drop for input chain; accepts established/related; accepts loopback; accepts SSH only from IPs in `client_ip_whitelist`; accepts Xray, Hysteria2, and AmneziaWG ports from any source.
- The firewall service (`nftables` or `ufw`) is enabled and started; rules persist across reboots.
- Re-running with no variable changes produces `changed=0`.
- Changing `xray_port` and re-running updates only the firewall rules; no service restart of Xray or Hysteria2 occurs from within this role.
- A Molecule scenario verifies: nft rules (or ufw status output) contain the expected port allowances (AC-6), `client_ip_whitelist` entries appear in SSH restrictions (AC-6), and idempotency (AC-3). AC-7 (network-level rejection from non-whitelisted IP) is documented as real-VPS only and excluded from Docker scenario.

## Notes

- Depends on TASK-0001 (vars schema, specifically all port variables and `client_ip_whitelist`).
- Prefer nftables over ufw for explicit rule control and scripted verification; ufw is acceptable if it simplifies Molecule verification. Pick one and document the choice in the role README.
- The `client_ip_whitelist` variable is a YAML list; the template must iterate it correctly. If the list is empty, SSH must still be accessible (fail-safe: do not lock out the operator).
- AC-7 (connection refused from non-whitelisted IP) requires a real NIC and cannot be tested in Docker. Document this gap explicitly in the Molecule scenario README and include a manual real-VPS test checklist.
- This role must not restart Xray, Hysteria2, or AmneziaWG — firewall rule changes do not require protocol service restarts.

## Implementation Plan

**Technology choice: nftables.** nftables is chosen over ufw because it allows the rendered ruleset to be verified line-by-line in Molecule without parsing human-readable prose output, and because `nft list ruleset` produces deterministic machine-readable output suitable for `grep`/`assert` checks. This choice is documented in the role README (Sub-step 5).

This role has two distinct concerns: (1) ruleset templating and (2) nftables service lifecycle management. They are kept in separate task files to preserve single responsibility. The role carries no handler that restarts Xray, Hysteria2, or AmneziaWG — firewall changes are self-contained.

### Sub-step 1 — Write failing Molecule tests (TDD first)

Create `ansible/roles/firewall/molecule/default/` before writing any task logic.

**`molecule/default/molecule.yml`** — declare the Docker driver with two platforms:

- `name: ubuntu2204`, image `geerlingguy/docker-ubuntu2204-ansible`, `privileged: true`
- `name: debian12`, image `geerlingguy/docker-debian12-ansible`, `privileged: true`

Set `provisioner.name: ansible` and `verifier.name: ansible`. Supply concrete variable overrides via `provisioner.inventory.group_vars.all` so every assertion has an exact expected value:

```yaml
ssh_port: 22
xray_port: 8443
hysteria2_port: 10443
awg_port: 51820
client_ip_whitelist:
  - "203.0.113.10"
  - "198.51.100.20"
```

**`molecule/default/prepare.yml`** — install the `nftables` package via `ansible.builtin.apt` before the role runs, simulating what the `prerequisites` role provides. This is required because the scenario does not invoke the `prerequisites` role.

**`molecule/default/converge.yml`** — a minimal playbook that applies only the `firewall` role, not the full `playbook.yml`, so the scenario is self-contained.

**`molecule/default/verify.yml`** — write `ansible.builtin.assert` tasks for the following cases (all must fail until the implementation in Sub-steps 2–4 is complete — that is the expected TDD red state):

1. `ansible.builtin.stat` on `/etc/nftables.conf` — assert `stat.exists == true` and `stat.mode == '0600'`.
2. `ansible.builtin.slurp` `/etc/nftables.conf`, base64-decode, assert the decoded string contains `"dport 8443 accept"` (Xray port), `"dport 10443 accept"` (Hysteria2 port), `"dport 51820 accept"` (AmneziaWG port). These checks satisfy AC-6.
3. `ansible.builtin.slurp` `/etc/nftables.conf`, assert the decoded string contains both `"203.0.113.10"` and `"198.51.100.20"` within the SSH allowance block, satisfying AC-6 (whitelist entries appear in SSH restrictions).
4. `ansible.builtin.slurp` `/etc/nftables.conf`, assert the decoded string contains `"type filter hook input priority 0"` and `"policy drop"`, confirming default-deny on the input chain.
5. `ansible.builtin.service_facts`, then assert `nftables.service` is in `enabled` state. Skip `state: active` assertion with an inline comment: Docker containers may not have a fully initialised systemd; the `started` state is verified on a real VPS.
6. **Idempotency** — Molecule's built-in idempotency check (second converge run) must produce `changed=0`. No additional task is needed here; Molecule enforces this automatically when `idempotency: true` is set in `molecule.yml`'s `provisioner` section.

**`molecule/default/README.md`** — stub file to be completed in Sub-step 5.

At this point `molecule converge` must fail because `roles/firewall/tasks/main.yml` does not exist. That is the expected TDD red state.

### Sub-step 2 — Author the nftables Jinja2 template in `roles/firewall/templates/nftables.conf.j2`

Create `ansible/roles/firewall/templates/nftables.conf.j2`. Single-responsibility: this file owns only the nftables ruleset shape — no task logic, no service management.

The template must render the following rule structure, driven entirely by variables:

```
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        # Accept established and related connections
        ct state established,related accept

        # Accept loopback
        iif "lo" accept

        # Accept SSH from whitelisted IPs only (fail-safe: accept all if list is empty)
        {% if client_ip_whitelist | length > 0 %}
        {% for ip in client_ip_whitelist %}
        ip saddr {{ ip }} tcp dport {{ ssh_port }} accept
        {% endfor %}
        {% else %}
        tcp dport {{ ssh_port }} accept
        {% endif %}

        # Accept protocol ports from any source
        tcp dport {{ xray_port }} accept
        udp dport {{ hysteria2_port }} accept
        udp dport {{ awg_port }} accept
    }
}
```

**Protocol-layer decisions to document in the template with inline comments:**

- Hysteria2 uses UDP; the template must use `udp dport` not `tcp dport` for `hysteria2_port`. Add a comment: `# hysteria2 is UDP-only`.
- AmneziaWG uses UDP; use `udp dport` for `awg_port`. Add a comment: `# AmneziaWG (WireGuard-based) is UDP-only`.
- Xray VLESS+XTLS-Vision+REALITY uses TCP; use `tcp dport` for `xray_port`. Add a comment: `# xray VLESS/REALITY is TCP`.
- The `flush ruleset` directive at the top ensures idempotency: every apply replaces the entire ruleset atomically. The nftables service will reload the file on each `nftables.service` restart or when `nft -f /etc/nftables.conf` is invoked.

**Single-responsibility flag:** Do not add any additional chains (e.g., `output`, `forward`) here — only the `input` chain is in scope per the acceptance criteria. Adding an `output` chain would be YAGNI and risks breaking container networking in Molecule.

**Edge case — empty `client_ip_whitelist`:** When the list is empty, the template falls back to `tcp dport {{ ssh_port }} accept` (allow SSH from any source). This prevents operator lockout. The Molecule scenario must include a second converge variant (or a separate test play in `verify.yml`) that passes `client_ip_whitelist: []` and asserts the fallback rule is present and no per-IP `ip saddr` rule appears. Add this assertion to `verify.yml` as a conditional block.

**Edge case — duplicate IPs in `client_ip_whitelist`:** If an operator accidentally lists the same IP twice, nftables will emit duplicate rules. This is harmless for correctness (the first matching rule accepts) but produces a non-zero `changed` count on every re-run because `ansible.builtin.template` compares file content. Document in the role README that `client_ip_whitelist` entries should be unique; add a `unique` Jinja2 filter (`client_ip_whitelist | unique`) to the template loop to silently deduplicate and preserve idempotency.

### Sub-step 3 — Implement ruleset deployment in `roles/firewall/tasks/rules.yml`

Create `ansible/roles/firewall/tasks/rules.yml` (sourced via `include_tasks:` from `tasks/main.yml`). Single-responsibility: this file owns only the `/etc/nftables.conf` file placement — no package installation, no service management.

**Task: Write `/etc/nftables.conf` from template**

Use `ansible.builtin.template` with:

- `src: nftables.conf.j2`
- `dest: /etc/nftables.conf`
- `owner: root`
- `group: root`
- `mode: '0600'`
- `notify: Reload nftables`

The `notify: Reload nftables` handler (defined in Sub-step 4) reloads the nftables ruleset whenever the rendered file changes. Because the handler uses `nft -f /etc/nftables.conf` rather than a service restart, it applies the new ruleset without touching any other service — satisfying the requirement that Xray, Hysteria2, and AmneziaWG are not restarted by this role.

**Idempotency mechanism:** `ansible.builtin.template` compares the rendered content against the file on disk. If the file is already identical (no variable changes), it reports `ok` and does not notify the handler. This is the correct idempotency mechanism; no additional `changed_when:` override is needed.

**Single-responsibility flag:** Do not install the `nftables` package in this file. Package installation belongs in `tasks/install.yml` (Sub-step 4). Mixing package and config concerns here would violate single responsibility.

### Sub-step 4 — Implement package installation and service management in `roles/firewall/tasks/install.yml` and `roles/firewall/handlers/main.yml`

**`ansible/roles/firewall/tasks/install.yml`** (sourced via `include_tasks:` from `tasks/main.yml` before `rules.yml`). Single-responsibility: package presence and service enablement only.

**Task: Ensure nftables package is present**

Use `ansible.builtin.apt` with:

- `name: nftables`
- `state: present`
- `update_cache: false`

Setting `update_cache: false` assumes the `prerequisites` role has already refreshed the APT cache. This is safe given the declared dependency on TASK-0001/TASK-0002.

**Task: Enable and start nftables service**

Use `ansible.builtin.service` with:

- `name: nftables`
- `state: started`
- `enabled: true`

This ensures the service is enabled at boot (rules persist across reboots) and is currently running. The task is idempotent — Ansible reports `ok` when the service is already in the desired state.

**`ansible/roles/firewall/handlers/main.yml`** — define a single handler:

```yaml
- name: Reload nftables
  ansible.builtin.command: nft -f /etc/nftables.conf
  changed_when: false
```

Using `nft -f /etc/nftables.conf` (not `service nftables restart`) applies the ruleset atomically without cycling the service. `changed_when: false` prevents the handler itself from inflating the `changed` count on the second run — the template task controls the changed signal; the handler is a side-effect-only reload.

**Single-responsibility flag:** This role defines no handlers named `Restart xray`, `Restart hysteria2`, or `Restart amneziawg`. The absence of those handler names must be verified during code review. If a reviewer sees a `notify:` call for any of those names in this role, it is a bug.

**`ansible/roles/firewall/tasks/main.yml`** — wire the sub-task files together:

```yaml
- name: Install nftables package and enable service
  ansible.builtin.include_tasks: install.yml

- name: Deploy nftables ruleset from template
  ansible.builtin.include_tasks: rules.yml
```

Order matters: the package must be installed before the config file is placed (the handler calls `nft`, which must be present).

### Sub-step 5 — Write the role README and Molecule scenario README

**`ansible/roles/firewall/README.md`**

Document the following:

- **Technology choice:** nftables is used (not ufw) because it provides deterministic machine-readable output via `nft list ruleset`, enabling reliable Molecule assertions. ufw's human-readable output would require fragile prose parsing.
- **Variables consumed:** `ssh_port`, `xray_port`, `hysteria2_port`, `awg_port`, `client_ip_whitelist` — all sourced from `ansible/vars/main.yml`.
- **Fail-safe:** If `client_ip_whitelist` is empty, SSH is permitted from any source to prevent operator lockout.
- **Protocol/port mapping rationale:** Xray is TCP; Hysteria2 and AmneziaWG are UDP. A reviewer changing a port variable must not accidentally swap `tcp dport` and `udp dport`.
- **No service restarts:** This role does not notify any handler for Xray, Hysteria2, or AmneziaWG. Firewall rule changes do not require protocol service restarts.
- **Maintenance obligation:** If `awg_port` or `hysteria2_port` transport protocol ever changes (e.g., Hysteria3 uses TCP), update `nftables.conf.j2` accordingly and re-run Molecule.

**`ansible/roles/firewall/molecule/default/README.md`**

Document the following:

- **ACs exercised in this scenario:** AC-3 (idempotency), AC-5 (template reflects variables), AC-6 (default-deny with explicit port allowances and whitelist SSH restrictions).
- **AC-7 gap:** Network-level rejection of non-whitelisted IPs (AC-7) requires a real NIC and network isolation. Docker containers share the host network namespace in ways that make `iptables`/`nftables` rule enforcement unreliable. AC-7 is excluded from this scenario.
- **Manual real-VPS test checklist for AC-7:**
  1. Deploy with `client_ip_whitelist: ["<operator-IP>"]`.
  2. From the operator IP, confirm SSH succeeds.
  3. From a second IP not in the whitelist (e.g., a second cloud instance), confirm `ssh -p <ssh_port> <vps-ip>` times out or is refused.
  4. Confirm `nft list ruleset` on the VPS shows no `ip saddr <second-IP>` rule in the SSH block.
  5. Run `make deploy` a second time with no variable changes; confirm `changed=0` in the Ansible summary.

### Edge cases derived from acceptance criteria

- **AC-3 (idempotency):** The `flush ruleset` in the template combined with `ansible.builtin.template`'s content comparison ensures the file is only written when variables change. The `Reload nftables` handler fires only when the file changes, not on every run. Verify with Molecule's built-in second-converge idempotency check.
- **AC-4 (variable rotation — xray_port only changes firewall):** Changing `xray_port` causes `ansible.builtin.template` to write a new `/etc/nftables.conf` and triggers `Reload nftables`. No Xray, Hysteria2, or AmneziaWG handler is notified. Verify in `verify.yml` by asserting the new port value appears in the rendered file and the old value does not.
- **AC-6 (default-deny policy):** The `policy drop` on the `input` chain must appear in the rendered file. Assert this explicitly in `verify.yml` step 4 above; do not rely on nftables default behavior.
- **Lockout guard:** Test the empty-whitelist fallback in a dedicated task in `verify.yml` using `when: client_ip_whitelist | length == 0`. The scenario's default `group_vars.all` sets a non-empty list; add a second verify play that overrides to `[]` and asserts `tcp dport {{ ssh_port }} accept` (without `ip saddr`) is present in the rendered file.
- **IPv6 consideration (out of scope but flagged):** The template uses `ip saddr` (IPv4 only). If `client_ip_whitelist` ever contains IPv6 addresses, the rule will be silently ignored by the `ip` table. This is a known limitation; document in the README that `client_ip_whitelist` accepts only IPv4 addresses in this version. IPv6 support (using `ip6 saddr` or `meta nfproto ipv6`) is a follow-up task and is not in scope per YAGNI.
