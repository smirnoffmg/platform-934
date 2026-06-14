---
id: TASK-0011
status: todo
feature_id: FEAT-0005
---

## Description

`config/sni-candidates.txt` exists in the repository as a curated plain-text list of FQDNs suitable for use as REALITY `serverName`, and `make rotate` can select from it randomly or be overridden with a specific SNI via a make variable. After this task, the operator has a ready-to-use starting list and a documented process for maintaining it.

Done looks like:

- `config/sni-candidates.txt` exists with at least 10 real FQDNs, one per line, each confirmed (at time of writing) to serve TLS 1.3 with HTTP/2 and be reachable from common Russian ISPs. Lines beginning with `#` are treated as comments and skipped by any consuming script.
- A `README` block (or `config/README.md`) explains: what makes a good SNI candidate (TLS 1.3, HTTP/2, not CDN-fronted on port 443 by a provider that blocks all its IPs, not a major Russian-blocked domain), how to verify a candidate (`openssl s_client -connect <fqdn>:443 -tls1_3`), and the operator's responsibility to keep the list current.
- `scripts/pick-sni.sh` is an executable POSIX sh script that reads `config/sni-candidates.txt`, strips comment lines, selects a random entry, and prints it to stdout. Exits non-zero with `ERROR: sni-candidates.txt is empty or no valid entry selected` if no non-comment lines exist or the file is missing.
- A shell test verifies: `pick-sni.sh` returns a non-empty string when the file has valid entries, and exits non-zero when given an empty file.

## Notes

- Depends on TASK-0010 (parallel; no code dependency, but both scripts feed into TASK-0012 and should be reviewed together).
- The `SNI=<value>` make variable override (AC-7) is implemented in the `make rotate` target (TASK-0012), not in this script. `pick-sni.sh` is a pure selection utility — it is not invoked when `SNI` is set.
- FQDNs in `config/sni-candidates.txt` must not include any Russian-government or Russian-state-owned domains; those are the most likely to be used as REALITY SNIs by other users, increasing fingerprint risk.
- The list is operator-maintained. Document that the operator should verify candidates periodically — domains change TLS behaviour, add HSTS preloading, or start blocking REALITY forward-proxy patterns.
- Do not hardcode IPs. FQDNs only; Xray resolves the SNI at runtime.
