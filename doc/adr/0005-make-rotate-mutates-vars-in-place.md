# 5. make rotate Mutates vars/main.yml In Place

Date: 2025-07-14

## Status

Proposed

## Context

FEAT-0005 introduces a `make rotate` target that changes the Xray port and SNI (and optionally regenerates secrets) on a live VPS. The rotation pipeline is: (1) generate a new port via `scripts/new-port.sh`, (2) optionally select a new SNI from `config/sni-candidates.txt`, (3) write the new values into `vars/main.yml`, (4) re-run `ansible-playbook`, (5) run `make check`.

`vars/main.yml` is the single source of truth for all protocol parameters (established in TASK-0001 / ADR-0001). It is committed to the repository and tracked by git. After `make rotate` runs, `vars/main.yml` contains new values that differ from the last commit.

A decision is required on how `make rotate` propagates new parameter values into this file: whether it writes directly to the working-tree file, generates a side-car file, or uses some other mechanism. This decision determines the git workflow operators must follow after every rotation, the rollback story, and the risk of accidental config loss.

## Decision

`make rotate` **writes new values directly into `vars/main.yml` in the working tree** using in-place string replacement (e.g., `sed -i` or a small Python one-liner) targeting the specific YAML keys (`xray_port`, `xray_server_name`). It does not commit, push, or stash the change. After a successful rotation, `vars/main.yml` is in a modified-but-uncommitted state.

The operator is responsible for committing the change:

```
git add ansible/vars/main.yml && git commit -m "rotate: port X → Y, SNI A → B"
```

This is documented in the `make rotate` success output and in the repository README. The operator is explicitly warned that `git checkout -- ansible/vars/main.yml` or `git stash` would revert to the pre-rotation config.

On connectivity check failure (`make check` exits non-zero), `make rotate` does **not** revert `vars/main.yml`. The file retains the new values so the operator can debug or re-run. Old and new port values are printed to stderr for diagnosis.

**Alternatives rejected:**

- **Atomic commit by `make rotate`:** `make rotate` could run `git add` and `git commit` automatically after a successful rotation. This keeps the repository in a clean state without operator action. Rejected because: (a) automating git commits in a Makefile target is surprising — operators expect `make` to affect build artifacts, not repository history; (b) it requires a clean working tree (no other unstaged changes) or a pre-commit hook interaction that is hard to predict; (c) it couples the rotation tool to the operator's git identity, signing key, and commit message conventions; (d) if the operator is mid-feature and has other staged changes, an automated commit interleaves rotation with unrelated work. The simpler approach is to treat `vars/main.yml` exactly as any other config file modified by a Makefile target and leave committing to the operator.

- **Side-car override file (e.g., `vars/rotation-override.yml`):** `make rotate` could write new values to a separate file that Ansible's `vars_files` loads after `vars/main.yml`, overriding only the rotated keys. This keeps `vars/main.yml` clean and committed. Rejected because: (a) it introduces two sources of truth for the same variables — any reader of `vars/main.yml` who does not know about the override file sees stale values; (b) the override file must itself be tracked or it is lost on the next `git clean`; (c) the playbook must be modified to load the override file, adding complexity with no benefit over direct edit; (d) when the operator later does a full re-deploy on a new VPS, it is unclear whether the override file's values are intended to persist. Direct in-place edit keeps one canonical file.

- **Environment variable injection (no file write):** `make rotate` could pass new port and SNI as `--extra-vars` to `ansible-playbook` without writing to `vars/main.yml`, then update the file only after a successful check. Rejected because: (a) if the process is interrupted between `ansible-playbook` and the file write, the VPS is running with parameters that are not recorded anywhere — a silent divergence between VPS state and repository state; (b) `make check` (FEAT-0003) reads from `vars/main.yml` to know which port to probe; if `vars/main.yml` has not been updated yet, `make check` probes the old port against a VPS that has already moved to the new port, producing a false failure. Writing to `vars/main.yml` before the playbook run keeps the file and the VPS state synchronized throughout the pipeline.

**Reversibility:** The in-place edit pattern is simple and has no external dependencies. Switching to any of the rejected alternatives later would require changing `scripts/new-port.sh`, the Makefile target, and operator documentation, but would not affect any Ansible role. The decision is **easily reversible** in isolation.

## Consequences

- **Positive:** `vars/main.yml` is always the single canonical source of truth — no side-car files, no environment overrides, no divergence between what Ansible reads and what `make check` probes.
- **Positive:** The implementation is a simple `sed -i` or equivalent; no new scripting dependencies are introduced.
- **Positive:** Failure-path behavior (file retains new values, operator can re-run or debug) is predictable and documented. The operator is never left with a VPS running parameters that are not recorded.
- **Negative:** After every successful `make rotate`, the operator must manually commit `vars/main.yml` to keep the repository consistent. If they do not, `git stash`, `git checkout`, or a colleague's `git pull --reset` could silently revert the live VPS's recorded config without reverting the VPS itself — creating a hidden divergence. This risk must be prominently documented.
- **Negative:** If `make rotate` is run while other changes to `vars/main.yml` are staged but not committed, the in-place edit may produce a merge conflict on the next `git add`. Operators must be warned to commit or stash any pending `vars/main.yml` changes before running `make rotate`.
- **Negative:** `config/sni-candidates.txt` is operator-maintained. If it is empty or all entries are blocked, `make rotate` must fail loudly (`ERROR: sni-candidates.txt is empty or no valid entry selected`) rather than proceeding with an empty or invalid SNI. This failure mode must be tested in the `scripts/new-port.sh` test suite.
- **Operational note:** The `SNI=<value>` make variable bypass (`SNI=example.com make rotate`) writes the provided value directly to `vars/main.yml` without reading `config/sni-candidates.txt`. The file need not exist when `SNI` is specified. This is the only case where `config/sni-candidates.txt` is not consulted.
