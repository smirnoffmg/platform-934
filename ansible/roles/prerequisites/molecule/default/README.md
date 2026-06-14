# Molecule default scenario — prerequisites role

## Acceptance criteria exercised

- **AC-3 (idempotency):** `molecule test` runs `converge` twice; the second run must report `changed=0` on all tasks. The `cache_valid_time: 3600` setting on the APT cache task ensures the cache-refresh task reports `ok` (not `changed`) on re-runs within the same session.
- **AC-9 (fresh-workstation reproducibility):** The scenario runs with only `ansible` and `molecule` installed — no pre-existing packages on the test containers beyond the base image.

## Known gap

`linux-headers-{{ ansible_kernel }}` cannot be installed or asserted inside Docker. Docker containers share the host kernel, and the kernel headers package matching the container's reported kernel string is not available in the Ubuntu/Debian APT mirrors for that string. The `dkms` package itself is installed and asserted. **Real-VPS runs (manual, pre-merge) must verify kernel header installation.**

The task in `tasks/main.yml` carries a `when: ansible_virtualization_type != 'docker'` guard; this guard is documented here and inline in the task file.

## Images used

| Platform name | Image                                   |
| ------------- | --------------------------------------- |
| ubuntu2204    | `geerlingguy/docker-ubuntu2204-ansible` |
| debian12      | `geerlingguy/docker-debian12-ansible`   |

These images ship with systemd stubs and `python3` pre-installed. Ansible's `package_facts` module requires Python and a working APT database; standard Ubuntu/Debian base images (e.g., `ubuntu:22.04`) lack both and would cause fact-gathering to fail.

## How to run

```bash
cd ansible/roles/prerequisites
molecule test          # full lifecycle (create → converge → idempotence → verify → destroy)
molecule converge      # apply role only (containers remain running)
molecule verify        # run verify.yml against running containers
molecule destroy       # tear down containers
```
