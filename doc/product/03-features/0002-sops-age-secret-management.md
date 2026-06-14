---
id: FEAT-0002
status: proposed
solution_hypothesis_id: SOL-0006
architectural_review_status: pending
---

# SOPS+age Secret Management

## Context

SOL-0006 requires that no plaintext secrets — Xray UUIDs, AmneziaWG pre-shared keys, Hysteria2 obfuscation passwords, TLS private keys — exist at rest in the repository checkout, the Ansible working directory, or on the VPS filesystem after provisioning. This is not an aspirational security property; it is a hard requirement because the repository is likely stored on a workstation that could be seized or imaged, and the VPS filesystem could be inspected by a provider with government access.

The chosen mechanism is SOPS (Secrets OPerationS) with age as the encryption backend. age is preferred over PGP because it has no key-server dependency, no expiry management overhead, and a simpler key format (`age1...` / `AGE-SECRET-KEY-1...`) that is straightforward to back up and restore. SOPS integrates directly with Ansible via the `community.sops` collection, allowing encrypted variable files to be decrypted transparently at play time without writing plaintext to disk.

This feature covers the full secret lifecycle: initial generation, encryption into the repository, playbook-time injection, and the hygiene invariant that no plaintext persists after the playbook run completes.

## Decision

**In scope:**

- One-time secret generation script (`make secrets`) that generates all required secrets (Xray UUID, AmneziaWG private key + PSK, Hysteria2 obfuscation password) using cryptographically appropriate sources (`uuid`, `wg genkey`, `openssl rand`) and immediately encrypts them into a SOPS-managed file (`secrets/secrets.sops.yaml`) using the operator's age public key.
- SOPS configuration (`.sops.yaml`) that specifies: the age public key(s) authorised to decrypt, and which file patterns are encrypted.
- Ansible integration via `community.sops` collection: the playbook decrypts `secrets/secrets.sops.yaml` at play time and injects values as Ansible variables. Decryption happens in memory; no plaintext file is written to the controller's filesystem.
- On the VPS, secrets are written only to service configuration files with `mode: 0600` owned by the service user (or `root`). They are not written to `/tmp`, Ansible fact cache, or any world-readable path.
- Documentation of the age key backup procedure (the operator must back up `AGE-SECRET-KEY-1...` independently; loss of the key means secrets must be rotated via `make secrets` and `make deploy`).
- Secret rotation: running `make secrets` generates new values and re-encrypts; `make deploy` then applies the new secrets. Old secrets are overwritten on the VPS.

**Out of scope:**

- Multi-operator key sharing or key escrow. Only one age key is supported. Adding a second recipient age key requires editing `.sops.yaml` and re-encrypting — this is a manual operator action not automated by this feature.
- Vault backends (HashiCorp Vault, AWS Secrets Manager, etc.). SOPS+age is the only supported secret store.
- Secret versioning or audit log. Previous secret values are not retained; SOPS file history exists only in git log.
- Automatic secret rotation on a schedule. Rotation is operator-initiated via `make secrets && make deploy`.
- Secrets for any service not in the proxy stack (e.g., monitoring credentials, SSH CA keys).

## Acceptance criteria

- **AC-1 (No plaintext in repository):** After running `make secrets`, the file `secrets/secrets.sops.yaml` exists in the repository and contains no plaintext secret values. Specifically: `grep -E 'uuid|private_key|psk|password' secrets/secrets.sops.yaml` returns only SOPS-encrypted ciphertext lines (beginning with `ENC[`), not bare UUID or key strings.
- **AC-2 (Decrypt requires age key):** Attempting to run `sops -d secrets/secrets.sops.yaml` on a workstation without the age private key (i.e., `AGE_SECRET_KEY` unset and `~/.config/sops/age/keys.txt` absent) fails with a non-zero exit code and a human-readable error. No partial plaintext is written.
- **AC-3 (Playbook decrypts in memory):** During `make deploy`, no plaintext file named `secrets*` or `vars_decrypted*` (or equivalent) is created in the Ansible working directory on the controller workstation. Verified by listing the working directory before and after the playbook run and confirming no new plaintext files appeared.
- **AC-4 (Secrets on VPS are 0600):** After `make deploy`, every file on the VPS that contains a secret value (Xray config, Hysteria2 config, AmneziaWG config) has filesystem permissions `0600` or stricter and is owned by `root` or the designated service user. Verified by `stat` on each config file path.
- **AC-5 (No secrets in world-readable paths):** After `make deploy`, the following VPS locations contain no secret values: `/tmp/`, `/var/log/`, `/etc/environment`, `/proc/*/environ` (for non-service processes), Ansible fact cache directory. Verified by scanning these paths for the deployed UUID and key substrings.
- **AC-6 (Secret rotation produces new values):** Running `make secrets` a second time produces a `secrets/secrets.sops.yaml` whose decrypted UUID value differs from the value produced by the first run. (Ensures `make secrets` generates fresh secrets rather than no-oping.)
- **AC-7 (Post-rotation deploy applies new secrets):** After running `make secrets` followed by `make deploy`, the Xray config file on the VPS contains the new UUID (matching the newly generated value), not the previous one.
- **AC-8 (make secrets is idempotent in structure):** Running `make secrets` on a workstation where `secrets/secrets.sops.yaml` already exists overwrites it with newly generated secrets rather than appending or erroring. The resulting file is valid SOPS-encrypted YAML (parseable by `sops -d`).
- **AC-9 (age key backup documentation):** The repository README or a dedicated `docs/secret-management.md` file contains explicit instructions for: (a) where the age private key is stored, (b) how to back it up, (c) what happens if the key is lost (must re-run `make secrets && make deploy`), and (d) how to add a second age recipient.

## Consequences

- **Single point of failure:** The age private key is the only credential that protects all secrets. If it is lost, all secrets must be regenerated and redeployed. If it is compromised, all secrets should be treated as compromised. Operators must understand this risk; the documentation requirement in AC-9 is the mitigation.
- **No secret history:** SOPS+age does not version secrets. If an operator needs to know what UUID was active 30 days ago, they must look at git history — and only if the SOPS file was committed at that point. This is acceptable for the single-user use case.
- **Ansible collection dependency:** `community.sops` must be installed (`ansible-galaxy collection install community.sops`). This is a new dependency beyond core Ansible. The `make deploy` entry point (FEAT-0001) must install it as a prerequisite or include it in `requirements.yml`.
- **SOPS version pinning:** SOPS file format can change across major versions. The `.sops.yaml` file and generated secrets files should document the SOPS version used. Future SOPS upgrades may require re-encryption.
- **No protection against memory forensics:** Secrets exist in plaintext in Ansible process memory during the play run. This is an accepted limitation — memory forensics requires physical or hypervisor-level access, which is outside the threat model.
