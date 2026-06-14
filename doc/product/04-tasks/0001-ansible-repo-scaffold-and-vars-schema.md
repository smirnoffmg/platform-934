---
id: TASK-0001
status: todo
feature_id: FEAT-0001
---

## Description

A reviewable Ansible project skeleton exists under `ansible/` with a canonical `vars/main.yml` file that declares every variable consumed by all roles. After this task, any role author can write templates and tasks against a stable, documented variable interface without needing to inspect other roles.

Done looks like:

- `ansible/` directory with `playbook.yml`, `inventory/` stub, `group_vars/`, `roles/`, and `vars/main.yml`.
- `vars/main.yml` declares all protocol-parameter variables with inline comments explaining each: Xray port, UUID, serverName; Hysteria2 port, obfuscation password; AmneziaWG port, `Jc`, `Jmin`, `Jmax`; SSH port; `client_ip_whitelist` list.
- `playbook.yml` lists all six roles in dependency order (prerequisites → amneziawg → xray → hysteria2 → firewall) with no role logic yet (each role directory may be empty stubs).
- A `README.md` under `ansible/` describes the variable file and the role execution order.
- No secrets appear in plaintext; the vars file uses placeholder strings that a SOPS decrypt step (FEAT-0002) will overwrite at deploy time.

## Notes

- This task establishes the shared contract: every subsequent role task (TASK-0002 through TASK-0006) depends on the variable names defined here. Variable renames after this task are a breaking change for all downstream tasks.
- Variable names must be stable and unambiguous — prefer `xray_port` over `port`, `awg_jc` over `jc`, etc.
- The `vars/main.yml` file is the single source of truth for all tunable parameters. Do not scatter defaults across `defaults/main.yml` in individual roles; put canonical values here.
- Supported OS constraint: `playbook.yml` should assert `ansible_distribution` is Ubuntu 22.04 or Debian 12 and fail fast with a readable message on any other target.
- No Molecule scenario is required for this task — there is no role logic to test yet.

## Implementation Plan

This task is pure scaffolding — no role logic, no service management. Every file created here acts as a contract for TASK-0002 through TASK-0006, so correctness of naming and structure matters more than completeness of content.

### Sub-step 1 — Create the directory skeleton

Create the following paths (empty files or minimal stubs where noted):

```
ansible/
  inventory/
    hosts.ini          # stub: single [vps] group, one placeholder host line
  group_vars/
    vps.yml            # empty for now; reserved for group-level overrides
  roles/
    prerequisites/     # empty stub — no tasks/main.yml yet
    amneziawg/         # empty stub
    xray/              # empty stub
    hysteria2/         # empty stub
    firewall/          # empty stub
  vars/
    main.yml           # canonical variable file (see Sub-step 2)
  playbook.yml         # (see Sub-step 3)
  README.md            # (see Sub-step 4)
```

Each role stub directory needs at minimum a `tasks/` subdirectory with an empty `tasks/main.yml` so that Ansible does not error when the role is referenced in `playbook.yml`. Single-concern check: `group_vars/vps.yml` is intentionally empty — no variable definitions go there; they belong exclusively in `vars/main.yml`.

### Sub-step 2 — Author `ansible/vars/main.yml` with the full variable schema

Declare every tunable parameter with an inline comment on the same line explaining its purpose and valid range or format. The complete set required is:

```
# Xray (VLESS + XTLS-Vision + REALITY)
xray_port: "PLACEHOLDER_XRAY_PORT"          # TCP port Xray listens on; integer 1–65535
xray_uuid: "PLACEHOLDER_XRAY_UUID"          # VLESS user UUID; UUIDv4 string
xray_server_name: "PLACEHOLDER_SNI"         # REALITY serverName; must be a real TLS-serving domain

# Hysteria2
hysteria2_port: "PLACEHOLDER_HY2_PORT"      # UDP port Hysteria2 listens on; integer 1–65535
hysteria2_obfs_password: "PLACEHOLDER_HY2_OBFS"  # Salamander obfuscation password; arbitrary string

# AmneziaWG
awg_port: "PLACEHOLDER_AWG_PORT"            # UDP port AmneziaWG listens on; integer 1–65535
awg_jc: "PLACEHOLDER_AWG_JC"               # Junk packet count; integer 3–10 recommended
awg_jmin: "PLACEHOLDER_AWG_JMIN"           # Minimum junk packet size in bytes
awg_jmax: "PLACEHOLDER_AWG_JMAX"           # Maximum junk packet size in bytes; must be ≥ awg_jmin

# SSH
ssh_port: 22                                # SSH port; change before locking firewall if non-standard

# Firewall / access control
client_ip_whitelist: []                     # List of operator CIDR strings allowed SSH access; e.g. ["203.0.113.5/32"]
```

All protocol-secret values use `"PLACEHOLDER_*"` strings — never real values. The SOPS decrypt step (FEAT-0002) will overwrite these at deploy time. `ssh_port` and `client_ip_whitelist` are non-secret operational values and may carry their real defaults here.

Edge cases to handle in the schema:

- `awg_jmin` / `awg_jmax` ordering: document in comments that `awg_jmax` must be ≥ `awg_jmin`; the firewall and AmneziaWG roles will validate this at runtime (not here).
- `client_ip_whitelist: []` empty list is a valid placeholder but means the firewall role will not restrict SSH by source IP. Document this behaviour in the comment.
- Port collision: no validation here, but comment that `xray_port`, `hysteria2_port`, `awg_port`, and `ssh_port` must all be distinct; the firewall role (TASK-0006) will enforce this.

### Sub-step 3 — Author `ansible/playbook.yml` with OS assertion and role order

`playbook.yml` must:

1. Target the `vps` host group.
2. Include a `pre_tasks:` block with an `assert` task that checks `ansible_distribution == "Ubuntu" and ansible_distribution_version == "22.04" or ansible_distribution == "Debian" and ansible_distribution_major_version == "12"`. The `fail_msg` must be human-readable: `"Unsupported OS: {{ ansible_distribution }} {{ ansible_distribution_version }}. Supported: Ubuntu 22.04, Debian 12."`.
3. List roles in the following order under `roles:`, matching the dependency graph from FEAT-0001:
   1. `prerequisites`
   2. `amneziawg`
   3. `xray`
   4. `hysteria2`
   5. `firewall`
4. Include `vars_files: [ vars/main.yml ]` so all roles share the canonical variable namespace.

No `become: true` at play level is needed yet (role stubs have no tasks), but include it as a comment noting that all role tasks will require privilege escalation so reviewers know to add it before TASK-0002.

Edge cases:

- The `pre_tasks` assert must run before any role — confirm `pre_tasks` ordering is not accidentally deferred by Ansible gather-facts behaviour. Use `gather_facts: true` explicitly so `ansible_distribution` is populated before the assert fires.
- Do not use `ansible.builtin.assert` with `quiet: true` — the failure message must be visible in CI output.

### Sub-step 4 — Author `ansible/README.md`

The README must cover exactly three sections (no more — YAGNI):

1. **Variable file (`vars/main.yml`):** List every variable name, its protocol, and the placeholder convention. Explicitly state that variable renames are a breaking change for TASK-0002 through TASK-0006.
2. **Role execution order:** Reproduce the ordered list from `playbook.yml` with a one-sentence explanation of each role's responsibility and which variables it consumes (forward reference to the task that implements it).
3. **OS support:** State supported targets (Ubuntu 22.04 LTS, Debian 12) and the fast-fail assertion location (`playbook.yml` pre_tasks).

Do not document SOPS usage, the Makefile, or Molecule here — those belong in FEAT-0002/FEAT-0003 documentation.

### Edge Cases Derived from Acceptance Criteria

| Edge case                                                                                                                                                | Source AC  | How this task addresses it                                                                                                                       |
| -------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ---- |
| `ansible_distribution_version` returns `"22.04"` (string) on Ubuntu but `ansible_distribution_major_version` is `"12"` (string) on Debian — types differ | AC-1, AC-9 | Assert uses the correct per-distro variable; document this asymmetry in a comment in `playbook.yml`                                              |
| `client_ip_whitelist: []` causes firewall role to skip SSH source restriction silently                                                                   | AC-7       | Comment in `vars/main.yml` warns that an empty list disables source-IP restriction on SSH                                                        |
| Port variables are placeholder strings, not integers — downstream Jinja2 templates must cast them                                                        | AC-5       | Comment in `vars/main.yml` explicitly flags that port placeholders are strings and templates must pipe through `                                 | int` |
| A sixth role name appears in `playbook.yml` but not in the directory skeleton — Ansible errors before any task runs                                      | AC-1       | Stub `tasks/main.yml` in every role directory prevents this; verify count matches (5 roles: prerequisites, amneziawg, xray, hysteria2, firewall) |
| `vars/main.yml` loaded via `vars_files` does not override inventory variables — any `group_vars/vps.yml` value takes precedence over `vars_files`        | AC-3, AC-4 | Keep `group_vars/vps.yml` empty and document the Ansible variable precedence risk in the README                                                  |
