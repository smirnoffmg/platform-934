---
id: FEAT-0003
status: proposed
solution_hypothesis_id: SOL-0006
architectural_review_status: pending
---

# Post-Deploy Connectivity Verification Gate

## Context

SOL-0006 specifies that `make deploy` must not report success until an automated connectivity check confirms the tunnel is actually working. This requirement exists because a playbook that reports `ok` but leaves a non-functional tunnel is operationally worse than a visible failure: the operator may close the terminal and discover hours later — under censorship pressure — that their proxy never worked.

The connectivity check is also the mechanism by which MET-0006 (deployment convergence time ≤ 15 minutes) is measured: the clock stops when the check passes, not when Ansible finishes. If Xray starts but REALITY is misconfigured — wrong serverName, wrong dest port, cert mismatch in the forwarded connection — the check will fail and `make deploy` will exit non-zero, forcing the operator to investigate before assuming the server is ready.

This feature defines the check itself: what it tests, what constitutes pass/fail, how it is invoked by `make deploy`, and what output it produces for debugging.

## Decision

**In scope:**

- A shell script (or small Python script) `scripts/check-connectivity.sh` invoked by `make deploy` after `ansible-playbook` exits 0.
- The check establishes a connection through the REALITY tunnel (using an Xray or compatible client binary on the controller workstation) and transfers ≥ 1 MB of data to a public endpoint (e.g., `http://speed.cloudflare.com/__down?bytes=1048576` or equivalent). Successful transfer at any non-zero throughput constitutes a pass.
- The check must complete within 60 seconds. If the transfer does not complete within 60 seconds, the check fails.
- On failure, the check prints to stderr: the exact error (connection refused, TLS handshake failure, timeout, transfer stalled), the VPS IP and port tested, and the client config used (excluding secrets). It then exits non-zero, causing `make deploy` to exit non-zero.
- On pass, the check prints to stdout: bytes transferred, wall-clock time, computed throughput in MB/s, and a single `CONNECTIVITY OK` line. It exits 0.
- The check is also available as a standalone `make check` target for use after manual changes or in monitoring scripts.

**Out of scope:**

- Testing Hysteria2 or AmneziaWG connectivity as part of the post-deploy gate. The gate tests the primary REALITY tunnel only. Fallback protocol verification is a separate concern (see SOL-0010 / future feature).
- Active-probing simulation. The check verifies user-path connectivity, not GFW-probe response behaviour (that is FEAT scope of a different solution hypothesis).
- Continuous monitoring or re-check on a schedule. The check runs once at deploy time and optionally on `make check`. Loop-based monitoring is out of scope.
- Measuring latency or jitter. The check is a binary pass/fail on transfer completion. Throughput is reported informatively but is not a pass/fail criterion.
- Generating a client config file for end-user devices. The check uses a temporary client config for its own verification; distributing client configs is out of scope for this feature.

## Acceptance criteria

- **AC-1 (Pass on working tunnel):** After a successful `make deploy` on a correctly configured VPS, `make check` exits 0 and prints `CONNECTIVITY OK` along with the bytes transferred (≥ 1 048 576), elapsed time, and throughput in MB/s.
- **AC-2 (Fail on misconfigured tunnel):** If Xray is stopped on the VPS (`systemctl stop xray`) and `make check` is run, it exits non-zero within 60 seconds and prints a human-readable error to stderr indicating the failure mode (e.g., "connection refused on port XXXX" or "TLS handshake timeout").
- **AC-3 (Fail on wrong serverName):** If the `serverName` variable in `vars/` is set to a value that does not match a reachable TLS 1.3 endpoint and `make deploy` is run with this bad value, `make check` (invoked automatically by `make deploy`) exits non-zero. `make deploy` exits non-zero. The operator is not left with a false-success deploy.
- **AC-4 (Timeout enforced):** If the VPS is reachable on the configured port but the tunnel stalls (e.g., data transfer begins but halts after a few KB), `make check` exits non-zero within 60 seconds, not after a longer system timeout. The exit code is non-zero and stderr contains the word "timeout" or "stalled".
- **AC-5 (make deploy exit code coupling):** `make deploy` exits 0 if and only if `ansible-playbook` exits 0 AND `make check` exits 0. If either fails, `make deploy` exits non-zero. This is verified by: (a) running a deploy with a stopped Xray service and confirming `make deploy` exits non-zero; (b) running a full correct deploy and confirming it exits 0.
- **AC-6 (Standalone make check target):** `make check` can be run independently of `make deploy` on a workstation that has already been through a successful deploy (VPS IP and port are read from the same `vars/` or inventory file used by the playbook). It requires no additional arguments.
- **AC-7 (Error output is actionable):** When `make check` fails, stderr contains at minimum: the VPS IP, the port number tested, and the error class (connection refused / TLS error / timeout / transfer stalled). A QA engineer reading only the stderr output can determine which layer failed without additional log access.
- **AC-8 (Check uses tunnel, not direct):** The connectivity check connects through the REALITY tunnel (i.e., traffic is proxied through Xray on the VPS), not directly to the VPS IP. Verified by confirming the egress IP reported by the download endpoint is the VPS IP, not the controller's IP.

## Consequences

- **Client binary dependency:** The check requires an Xray (or equivalent) client binary on the controller workstation to establish the tunnel connection. This is an additional tool dependency beyond `ansible`, `sops`, and `age`. It must be documented in the setup guide and its absence must produce a clear error, not a silent failure.
- **False negatives on provider-side rate limiting:** Some providers throttle outbound bandwidth for new VMs during the first minutes after provisioning. A slow provider may cause the 60-second timeout to fire even on a correctly configured server. Operators should be aware that a single `make check` failure immediately after first deploy is not conclusive; `make check` can be re-run manually.
- **Check does not validate AmneziaWG or Hysteria2:** The gate's scope is the primary REALITY tunnel. A deploy where Hysteria2 is misconfigured will still pass the gate. Fallback protocol validation requires a separate check that is out of scope here.
- **Single-endpoint download target:** If the check endpoint (`speed.cloudflare.com` or equivalent) is itself blocked at the VPS provider or in the test network, the check may fail for reasons unrelated to the tunnel configuration. A fallback download endpoint should be configurable via a variable.
