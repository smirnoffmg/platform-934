---
id: TASK-0010
status: todo
feature_id: FEAT-0005
---

## Description

`scripts/new-port.sh` is an executable shell script that selects a random unused port in the range 47001–65535, verifies it does not conflict with any port already in `vars/main.yml`, verifies it is not currently bound on the local workstation, and writes the selected port to stdout. After this task, `make rotate` (TASK-0012) can call this script to obtain a collision-free port without any manual input.

Done looks like:

- `scripts/new-port.sh` is executable (`chmod +x`) and POSIX sh compatible.
- Selects a random integer in [47001, 65535].
- Reads current port values from `vars/main.yml` (`xray_port`, `hysteria2_port`, `awg_port`, `ssh_port`) and rejects any candidate that matches an existing value; retries up to 10 times before exiting non-zero with `ERROR: Could not find an unused port after 10 attempts`.
- Checks whether the candidate port appears in `ss -ltn` output on the local workstation; rejects and retries if it does.
- Prints exactly the selected port integer to stdout (no trailing text or newline decoration beyond a single `\n`).
- A shell test (runnable with `bash scripts/test-new-port.sh` or as part of `make test`) verifies: output is an integer in range, output does not collide with ports already present in a fixture `vars/main.yml`.

## Notes

- Depends on TASK-0001 (vars file at `vars/main.yml` with stable variable names `xray_port`, `hysteria2_port`, `awg_port`, `ssh_port`).
- The script must be POSIX sh, not bash — `make rotate` (TASK-0012) may invoke it from a `sh -c` context.
- `ss` is assumed present (it is part of `iproute2`, available on all supported targets). If `ss` is absent, print a warning to stderr and skip the local-bind check rather than failing hard — the primary collision guard is the vars-file check.
- The VPS-side port-availability check (whether the candidate port is free on the remote host) is deferred to Ansible: the Ansible role will attempt to bind the port and fail if it is taken. Document this in a comment in the script.
- Do not write to `vars/main.yml` from within this script; the caller (`make rotate`) is responsible for substituting the value into the file.
