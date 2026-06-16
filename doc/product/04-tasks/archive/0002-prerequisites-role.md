---
id: TASK-0002
status: done
feature_id: FEAT-0001
completed_at: "2026-06-16T11:05:59.379Z"
commit_sha: 954ef583e9cc5c65deda88def98ef262c1e28324
---

## Description

An idempotent `prerequisites` Ansible role installs all APT packages and kernel headers required by the rest of the playbook. After this task, every subsequent role can assume its system-level dependencies are present without managing them itself.

Done looks like:

- `roles/prerequisites/tasks/main.yml` installs: `linux-headers-$(uname -r)`, `dkms`, `nftables` (or `ufw`), `curl`, `unzip`, and any other packages needed by downstream roles.
- Running the role twice on the same host produces `changed=0` on the second run (APT `cache_valid_time` is set; package tasks use `state: present`).
- A Molecule scenario (Docker driver, Ubuntu 22.04 image and Debian 12 image) verifies that all expected packages are installed after convergence and that a second `molecule converge` produces zero changed tasks.
- The scenario is named clearly (e.g., `molecule/default/`) and its `INSTALL.rst` or `README` states which ACs it exercises (AC-3, AC-9).

## Notes

- Depends on TASK-0001 for the repo structure and `playbook.yml` role order.
- Kernel headers (`linux-headers-$(uname -r)`) cannot be installed in Docker (no real kernel); skip that assertion in the Molecule verify step and document the gap explicitly in the scenario README. The DKMS package itself can still be installed and asserted.
- Use `ansible.builtin.apt` with `update_cache: true` and `cache_valid_time: 3600` to avoid redundant apt-get updates on re-runs.
- Do not install protocol binaries (Xray, Hysteria2) here — those belong in their respective roles.

## Implementation Plan

This role has a single concern: guarantee that all system-level APT packages required by downstream roles are present, and that the guarantee is idempotent. No service management, no configuration templating — just package installation.

### Sub-step 1 — Write failing Molecule tests (TDD first)

Create `ansible/roles/prerequisites/molecule/default/` with the following files before writing any task logic:

**`molecule/default/molecule.yml`** — declare the Docker driver with two platforms:

- `name: ubuntu2204`, image `geerlingguy/docker-ubuntu2204-ansible` (or equivalent systemd-capable image)
- `name: debian12`, image `geerlingguy/docker-debian12-ansible`

Both platforms must run in privileged mode (`privileged: true`) so that `apt` works inside the container without a real init. Set `provisioner.name: ansible` and `verifier.name: ansible`.

**`molecule/default/verify.yml`** — write `ansible.builtin.package_facts` followed by `ansible.builtin.assert` tasks that fail unless the following packages appear in `ansible_packages`:

- `dkms`
- `nftables`
- `curl`
- `unzip`
- `gpg` (required by downstream roles that add APT signing keys, e.g. xray, hysteria2)

Do **not** assert `linux-headers-*` here (no real kernel in Docker). Add a comment block in `verify.yml` explicitly naming this gap and referencing AC-3.

Also add an `ansible.builtin.assert` that the second converge produced `changed=0`. The Molecule built-in idempotency check covers this automatically when `molecule test` is run, but document in `verify.yml` comments which AC it maps to (AC-3, AC-9).

**`molecule/default/README.md`** — stub the file now (content authored in Sub-step 4). Its existence in the test run is required before implementation begins so that `molecule test` surfaces a failing lint step rather than silently skipping documentation.

At this point `molecule converge` must fail because `roles/prerequisites/tasks/main.yml` does not exist yet. That failing run is the expected TDD red state.

### Sub-step 2 — Implement `roles/prerequisites/tasks/main.yml`

Create `ansible/roles/prerequisites/tasks/main.yml` with exactly two `ansible.builtin.apt` tasks — no more, no fewer, to keep the role single-responsibility:

**Task A — cache refresh:**

```
name: Update APT cache (bounded, idempotent)
ansible.builtin.apt:
  update_cache: true
  cache_valid_time: 3600
```

`cache_valid_time: 3600` means APT is only refreshed if the cache is older than one hour. On the second run within the same hour, this task reports `ok` rather than `changed`. This directly satisfies AC-3.

**Task B — install packages:**

```
name: Install prerequisite packages
ansible.builtin.apt:
  name:
    - dkms
    - nftables
    - curl
    - unzip
    - gpg
    - linux-headers-{{ ansible_kernel }}
  state: present
```

Using `state: present` (not `state: latest`) ensures the task reports `ok` on re-runs when packages are already installed, satisfying AC-3. `ansible_kernel` is the correct Ansible fact for the running kernel version — equivalent to `$(uname -r)` but resolved at fact-gather time without a shell call.

Single-responsibility check: `ansible_kernel`-based header installation is in the same task list as the other packages. This is acceptable because the concern is still "install APT packages." Do NOT add any `template:`, `service:`, or `copy:` tasks here — those would introduce a second responsibility and must be flagged and rejected in review.

Create `ansible/roles/prerequisites/defaults/main.yml` as an empty file (or with a comment) to make the role structure complete per Ansible conventions. Do NOT place any variable definitions there per the TASK-0001 contract that `ansible/vars/main.yml` is the single source of truth.

Create `ansible/roles/prerequisites/meta/main.yml` with at minimum:

```yaml
galaxy_info:
  role_name: prerequisites
  min_ansible_version: "2.15"
dependencies: []
```

`dependencies: []` is explicit — no role-level dependency declarations; role order is managed solely by `playbook.yml`.

### Sub-step 3 — Wire the role into `playbook.yml` and verify ordering

Confirm (do not change) that `ansible/playbook.yml` already lists `prerequisites` as the first role in the `roles:` block, before `amneziawg`, `xray`, `hysteria2`, and `firewall`. This ordering was established in TASK-0001. If the file does not yet list the role (stub state), add `prerequisites` as the first entry. No other changes to `playbook.yml` are in scope for this task.

Run `molecule test` (both platforms) to confirm:

1. First converge installs all expected packages — `verify.yml` assertions pass.
2. Molecule's built-in idempotency check (second converge) reports `changed=0` — AC-3 satisfied.
3. `linux-headers-*` assertion is absent from verify, confirming the Docker gap is correctly excluded.

### Sub-step 4 — Author `molecule/default/README.md`

The README must include:

- **ACs exercised:** AC-3 (idempotency — zero changed tasks), AC-9 (fresh-workstation reproducibility — scenario runs with only `ansible` installed).
- **Known gap:** `linux-headers-{{ ansible_kernel }}` cannot be installed or asserted inside Docker because Docker containers share the host kernel and do not provide kernel headers via APT. The `dkms` package is still installed and asserted. Real-VPS runs (manual, pre-merge) must verify kernel header installation.
- **How to run:** `cd ansible && molecule test -s default`.
- **Images used and why:** explain that `geerlingguy/docker-ubuntu2204-ansible` and `geerlingguy/docker-debian12-ansible` are used because they ship with `systemd` stubs and `python3`, which Ansible requires for `package_facts` to work correctly.

## Edge Cases

The following edge cases are derived directly from the feature's acceptance criteria and the notes above:

1. **`linux-headers-{{ ansible_kernel }}` unavailable in Docker (AC-1 / AC-3 gap):** The package task will fail inside Molecule's Docker container because the container's kernel string does not match any headers package in the Ubuntu/Debian APT mirrors. Mitigation: add a `when: ansible_virtualization_type != 'docker'` condition to the kernel-headers item, or split it into its own task with that guard. The guard must be documented in both `tasks/main.yml` (inline comment) and `molecule/default/README.md`.

2. **APT lock contention on first boot (AC-3 / AC-9):** Cloud VPS images often run `unattended-upgrades` or `apt-daily` in the background during first boot. The `ansible.builtin.apt` module does not retry automatically. Add a `retries: 5` / `delay: 10` / `until: result is succeeded` loop (using `register: result`) on Task B to handle transient lock errors without failing the playbook. This is not "gold-plating" — it directly prevents AC-9 failures on fresh VPS deploys.

3. **`cache_valid_time` and the second-run idempotency (AC-3):** If Task A and Task B are separate `ansible.builtin.apt` calls and the cache was fresh when Task A ran, Task B must not trigger another `apt-get update`. Confirm that setting `update_cache: true` only on Task A (the dedicated cache task) and omitting it from Task B achieves this. Do not set `update_cache: true` on Task B — doing so would cause every package-install task to report `changed` regardless of cache age.

4. **`nftables` vs. `ufw` co-installation conflict:** On Ubuntu 22.04, `ufw` and `nftables` can coexist as packages but may conflict when both are active as services. This role installs only the `nftables` package (`state: present`), never enables or starts the service — that is the firewall role's responsibility (TASK-0006). Do not include `ufw` in the package list here; the firewall role owns that decision. If downstream review determines `ufw` is preferred over `nftables`, the change must be made in this file, but it is a single-line change with no logic impact on this role.

5. **`gpg` already installed under a different package name (Debian 12):** On Debian 12 `bookworm`, `gpg` is provided by the `gpg` package but the binary may already be present via `gnupg` or `gnupg2`. Using `state: present` with the canonical package name `gpg` is safe — APT will mark it `ok` if any provider satisfies it. No special handling needed, but the Molecule verify step should assert `gpg` the package name, not the binary path, to avoid false negatives.

6. **Molecule idempotency check scope (AC-3):** Molecule's built-in idempotency check runs the converge playbook a second time and fails if any task reports `changed`. The `update_cache` task with `cache_valid_time: 3600` will always report `ok` on the second run within the same Molecule session (cache is seconds old). No special handling is needed, but reviewers must verify this is true: if `cache_valid_time` is accidentally omitted, the cache task will report `changed` on every run and break AC-3 at the Molecule level before it ever reaches a real VPS.
