---
id: MET-0003
status: proposed
problem_hypothesis_id: PROB-0001
---

# Mean Config Survival Duration

## What it measures

How long a deployed config remains unblocked before a burn event forces rotation — the primary causal factor in user-experienced uptime alongside rotation time.

## Definition

**Survival duration** = time from successful deployment (first passing connectivity check) to the first detected block event on either the China or Russia test path.

**Block event** = two consecutive failing polls from the polling daemon (MET-0001), preceded by at least one passing poll in the same deployment window.

Mean computed over all deployments within a 90-day observation window.

## Collection method

Derived automatically from the MET-0001 polling daemon logs. Each deployment is timestamped at deploy time; each burn event is timestamped when detected. Survival duration = burn timestamp − deploy timestamp. Where no burn event occurs, the deployment is right-censored at observation window end.

## Threshold

≥ 14 days mean config survival duration across all deployments in the observation window.

## Rationale

Uptime (MET-0001) is a function of two variables: how long configs survive and how fast rotation restores connectivity. Without this metric, a poor MET-0001 score is undiagnosable — it could mean configs burn in hours (protocol problem) or that rotation takes 45 minutes (ops problem). 14 days is chosen as a threshold that, combined with a ≤ 5-minute rotation time (MET-0005), yields theoretical uptime well above the 95% threshold. If survival duration is shorter, the protocol stack needs reassessment; if longer, the provisioner tooling is the bottleneck.
