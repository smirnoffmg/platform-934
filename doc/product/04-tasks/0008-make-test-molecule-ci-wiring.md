---
id: TASK-0008
status: todo
feature_id: FEAT-0001
---

## Description

A `make test` Makefile target runs all Molecule scenarios across all roles in sequence and exits 0 only when every scenario passes. After this task, CI can gate any PR touching an Ansible role by running `make test`, satisfying AC-11.

Done looks like:

- `Makefile` target `test` discovers and runs the Molecule scenario for each role (`prerequisites`, `amneziawg`, `xray`, `hysteria2`, `firewall`) using `molecule test` in each role's directory.
- The output for each scenario is prefixed with the role name and lists the ACs it exercises, matching the documentation requirement in AC-11.
- `make test` exits 0 only when all scenarios pass; the first failure halts execution and identifies which role's scenario failed.
- A CI configuration file (e.g., `.github/workflows/test.yml`) runs `make test` on pull requests targeting any file under `ansible/roles/`. The workflow requires only `ansible`, `molecule[docker]`, and Docker to be available — no real VPS, no age key.
- Running `make test` locally on a workstation with Docker and the required Python packages succeeds within a reasonable time (documented in `ansible/README.md`).

## Notes

- Depends on TASK-0002 through TASK-0006 (each role must have a passing Molecule scenario before this wiring task is meaningful).
- Depends on TASK-0007 (Makefile exists so `test` target can be added alongside `deploy`).
- The `amneziawg` Molecule scenario skips kernel-module assertions in Docker (documented in TASK-0003); `make test` must still exit 0 when those assertions are correctly marked as skipped, not failed.
- Pin the `molecule` and `molecule-plugins[docker]` versions in a `requirements-dev.txt` (or `pyproject.toml` dev dependency) to ensure reproducible CI runs. Document the pinned versions in `ansible/README.md`.
- Real-VPS tests (AC-1 AmneziaWG portion, AC-2, AC-7, AC-8) are explicitly not part of `make test`. The CI workflow README must state this gap and link to the manual real-VPS test checklist.
