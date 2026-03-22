# Explain DAG — Agent 3: Causal Reasoning

Explain the causal DAG structure in plain English: describe nodes, edges,
causal story, and economic rationale. Optionally focus on a specific node
or pathway. Read-only — no DB writes.

## Usage

```
/explain-dag [node=<node_name>] [lob=<lob>]
```

Examples:
```
/explain-dag
/explain-dag node=development_factor
/explain-dag node=large_loss_event lob=WC
```

---

## Step 1 — Load DAG

Read `inst/dag/reserving_dag.txt` and parse with `dagitty`.

---

## Step 2a — If No Node Specified: Full DAG Overview

Print the full DAG summary:

```
AXIOM-P&C Causal DAG — Overview
═══════════════════════════════════════════════════════════
 File:    inst/dag/reserving_dag.txt
 Nodes:   22
 Edges:   31
 Type:    Directed Acyclic Graph (dagitty format)

NODE GROUPS
───────────────────────────────────────────────────────────
 Exposure drivers (upstream):
   earned_premium, policy_count, average_premium

 Claim dynamics:
   claim_frequency, claim_severity, large_loss_event,
   claim_reporting_delay, claim_settlement_lag

 Reserve mechanics:
   initial_reserve, reserve_strengthening, ibnr_estimate

 Development factors:
   development_factor, calendar_year_effect, accident_year_trend

 External environment:
   inflation_rate, litigation_trend, regulatory_change,
   economic_cycle, medical_cost_trend

 Outcomes (downstream):
   cumulative_paid, cumulative_incurred, ata_factor

CAUSAL STORY
───────────────────────────────────────────────────────────
 The DAG encodes the view that loss development is primarily driven by:
 1. Exposure volume (earned_premium → claim_frequency)
 2. Claim dynamics (frequency × severity → initial_reserve)
 3. Development patterns shaped by reporting lags, settlement practices,
    and calendar-year inflation/litigation trends
 4. Reserve adequacy adjustments that create diagonal effects

 The economic rationale follows CAS reserving literature: triangles are
 not i.i.d. — development factors share systematic drivers that must be
 conditioned on to estimate unbiased IBNR.
═══════════════════════════════════════════════════════════
```

---

## Step 2b — If Node Specified: Node Deep Dive

For the requested node, show:

```
Node: development_factor
══════════════════════════════════════════════════
 Description:
   The age-to-age factor (ATA) representing how much cumulative
   paid losses grow from one development period to the next.
   A factor of 1.0 means no additional development; factors > 1.0
   indicate continuing loss emergence.

 Direct Parents (causes):
   ← claim_reporting_delay    (late-reported claims inflate lag-N factors)
   ← reserve_strengthening    (bulk strengthening creates diagonal spikes)
   ← large_loss_event         (single large claims distort the triangle)
   ← litigation_trend         (higher litigation increases development tail)
   ← calendar_year_effect     (systemic trends across accident years)

 Direct Children (effects):
   → ata_factor               (development_factor IS the ATA factor)
   → ibnr_estimate            (development factors drive IBNR projection)

 Backdoor paths (confounders to adjust for):
   Path 1: development_factor ← calendar_year_effect ← inflation_rate
   Path 2: development_factor ← litigation_trend ← regulatory_change
   Path 3: development_factor ← large_loss_event ← economic_cycle
   Adjustment set: {accident_year, earned_premium}

 LOB-specific notes (WC):
   Workers' Comp development factors are sensitive to:
   - Occupational disease latency (long tails)
   - State-level benefit changes (regulatory_change)
   - Medical cost inflation (medical_cost_trend)
══════════════════════════════════════════════════
```

---

## Notes

- Read-only — does not modify any files or database tables
- DAG must exist at `inst/dag/reserving_dag.txt`
- For anomaly-specific causal traces, use `/trace-anomaly`
