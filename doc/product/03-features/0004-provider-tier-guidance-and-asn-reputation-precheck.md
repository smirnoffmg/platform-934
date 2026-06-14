---
id: FEAT-0004
status: proposed
solution_hypothesis_id: SOL-0006
architectural_review_status: pending
---

# Provider Tier Guidance and Pre-Deploy ASN Reputation Check

## Context

SOL-0006 identifies IP/ASN reputation as equally important as protocol choice for Russia targets. TSPU's 16 KB curtain specifically targets foreign datacenter IP ranges — Hetzner, DigitalOcean, OVH — that are trivially fingerprinted by their published ASN prefixes. A correctly configured REALITY tunnel running on a flagged ASN will be frozen after ~25 packets regardless of protocol quality. The provisioner must therefore guide the operator toward clean-IP providers before deployment, not after.

The problem is that ASN reputation changes faster than any static document can track. A provider that was clean in Q1 may be on a TSPU blocklist by Q3. This creates a dual requirement: (1) a curated, versioned provider tier list that documents currently recommended providers with rationale, and (2) an automated pre-deploy ASN reputation check that queries live data and warns the operator if the target VPS IP is in a known-blocked ASN — before `ansible-playbook` runs and before the operator has committed 15 minutes of provisioning time to a server that will not work.

This feature does not prevent the operator from deploying to a flagged ASN. It warns and requires explicit acknowledgement. The decision authority remains with the operator.

## Decision

**In scope:**

- A `docs/providers.md` file containing a tiered provider list with at minimum: Russia-recommended tier (clean-IP providers in Finland, Germany, Latvia — specifically excluding Hetzner, DigitalOcean, OVH, Vultr, Linode as of the document's version date), China-recommended tier (CN2 GIA Asia-Pacific providers), and a generic European baseline tier. Each entry includes: provider name, datacenter locations, ASN(s), and the rationale for its tier placement (e.g., "Not on Roskomnadzor-adjacent blocklists as of YYYY-QQ").
- A `docs/providers.md` header that states the document version date and instructs the operator to verify ASN reputation independently before deploying, because the list may be stale.
- A pre-deploy check script `scripts/check-asn.sh` (or equivalent) that: accepts the VPS IP as input, queries a public ASN lookup API (e.g., `ipinfo.io/AS` or `bgpview.io`) to retrieve the ASN number and organisation name, compares the ASN against a bundled blocklist of known-flagged ASNs for Russia (Hetzner: AS24940, DigitalOcean: AS14061, OVH: AS16276, and equivalents), and prints a WARN or PASS result.
- The pre-deploy check is integrated into `make deploy` as the first stage, before SOPS decrypt and before `ansible-playbook`. If the ASN is on the blocklist, the check prints a prominent warning, states the ASN name, and prompts the operator to confirm (or accept `--force` flag to skip interactively). It does not automatically abort.
- The bundled ASN blocklist is a plain text or YAML file in the repository, versionable and operator-editable.

**Out of scope:**

- Real-time or continuous ASN monitoring after deployment. The check runs once at deploy time. Ongoing monitoring of ASN reputation is outside scope.
- Automated provider selection or VM provisioning. The check operates on an already-provisioned VPS IP. Choosing and provisioning the VPS is the operator's responsibility.
- China-specific ASN blocklist. The Russia blocklist is the primary deliverable; a China-specific list may be added in a follow-up.
- BGP routing analysis or path-level inspection. The check uses ASN organisation name only, not routing table analysis.
- Provider pricing, bandwidth, or SLA comparison. `docs/providers.md` covers IP reputation and region only.
- Automatic update of the bundled ASN blocklist from an external feed. Updates are manual and committed to the repository.

## Acceptance criteria

- **AC-1 (Provider doc exists and is structured):** `docs/providers.md` exists in the repository and contains at minimum three named sections: Russia-recommended providers, China-recommended providers, and Excluded providers. Each section lists at least three entries. Each entry includes provider name, at least one ASN number, and a one-sentence rationale for its tier placement.
- **AC-2 (Provider doc version-dated):** `docs/providers.md` contains a visible "Last reviewed" date (e.g., `<!-- Last reviewed: 2025-Q2 -->` or a header field) and a disclaimer stating the list may be stale and directing operators to verify ASN reputation before deploying.
- **AC-3 (Excluded providers named):** `docs/providers.md` Excluded section includes at minimum: Hetzner (AS24940), DigitalOcean (AS14061), OVH (AS16276), with rationale referencing TSPU blocklist targeting of these ASNs.
- **AC-4 (ASN check — known-bad ASN warns):** Running `scripts/check-asn.sh <IP-in-Hetzner-range>` (e.g., any IP in `AS24940`) prints a warning to stdout containing the text "WARN" and the ASN organisation name ("Hetzner") and exits with code 1 (warning, not hard failure).
- **AC-5 (ASN check — clean ASN passes):** Running `scripts/check-asn.sh <IP-in-known-clean-ASN>` (e.g., a provider on the Russia-recommended tier) prints a line containing "PASS" and the ASN organisation name, and exits with code 0.
- **AC-6 (ASN check — unknown ASN warns conservatively):** Running `scripts/check-asn.sh <IP>` where the IP's ASN is not in either the blocklist or the approved list prints a line containing "UNKNOWN ASN" and the organisation name, and exits with code 1 (warns, does not pass silently).
- **AC-7 (Pre-deploy integration — warn does not abort automatically):** When `make deploy` is run with a VPS IP in a blocklisted ASN, the pre-deploy check prints the warning and either (a) prompts the operator for confirmation (y/N) in interactive mode, or (b) aborts with exit code 1 and instructs the operator to re-run with `FORCE_DEPLOY=1 make deploy` to override. In no case does `make deploy` silently proceed past a blocklisted ASN without operator acknowledgement.
- **AC-8 (Pre-deploy integration — pass proceeds unattended):** When `make deploy` is run with a VPS IP in a non-blocklisted ASN, the pre-deploy check exits 0 and `make deploy` continues to the SOPS decrypt and `ansible-playbook` stages without prompting.
- **AC-9 (Blocklist is operator-editable):** The ASN blocklist file (e.g., `config/asn-blocklist.yaml`) is a plain text or YAML file in the repository. An operator can add or remove ASN entries by editing this file and committing it. The check script reads from this file, not from a hardcoded list in the script body.
- **AC-10 (API failure is non-blocking):** If the ASN lookup API is unreachable (network error, rate limit, DNS failure), `scripts/check-asn.sh` prints a warning stating the lookup failed and the reason, and exits with code 1. `make deploy` in this case follows the same warning-acknowledgement flow as AC-7. It does not silently proceed as if the ASN were clean.

## Consequences

- **Staleness risk is the primary risk of this feature.** The provider tier list and bundled ASN blocklist are static documents in the repository. TSPU's blocked ASN set changes without notice. An operator who trusts a stale list and deploys to a newly-blocked ASN will experience the 16 KB curtain with no warning at deploy time (because the check only knows about ASNs in the bundled list). The "Last reviewed" date and the disclaimer in AC-2 are the only mitigations within scope.
- **External API dependency for live check:** `scripts/check-asn.sh` depends on a third-party IP-to-ASN API. If that API changes its response format or requires authentication, the check will break. The script should be written to fail loudly (AC-10), not silently pass, when the API is unavailable.
- **Operator override exists:** The `--force` / `FORCE_DEPLOY=1` escape hatch (AC-7) means the check can always be bypassed. This is intentional — operators in testing environments or deploying to non-Russia targets should not be blocked by Russia-specific ASN rules — but it means the check is advisory, not enforcement.
- **Maintenance burden:** The provider tier list and ASN blocklist require periodic review (suggested: quarterly). If no process is established for this review, the feature's value degrades rapidly. A follow-up task should assign an owner and schedule for blocklist maintenance.
- **No China blocklist in v1:** The Russia TSPU blocklist is the primary deliverable. China GFW's IP blocking patterns are less ASN-deterministic (GFW uses active probing rather than ASN-wide blocks), so a China-specific blocklist would have different characteristics and is deferred.
