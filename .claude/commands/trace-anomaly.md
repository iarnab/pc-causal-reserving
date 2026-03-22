# Trace Anomaly — Agent 3: Causal Reasoning

Trace a specific anomaly flag through the causal DAG to identify the
most plausible causal pathway. Reads from `anomaly_flags` and the DAG
definition; writes a causal trace to `causal_context_docs`.

## Usage

```
/trace-anomaly <lob> [grcode=<company>] [accident_year=<year>] [development_lag=<lag>]
```

Examples:
```
/trace-anomaly WC                              ← all flagged cells for WC
/trace-anomaly WC grcode=353
/trace-anomaly WC grcode=353 accident_year=1992 development_lag=3
```

---

## Pre-conditions

1. `anomaly_flags` must have rows for the requested cell(s).
   If none: `ERROR — run /scan-anomalies <lob> first.`
2. The DAG definition must exist at `inst/dag/reserving_dag.txt`.

---

## Step 1 — Load the DAG

Read the canonical DAG from `inst/dag/reserving_dag.txt`.
Parse with `dagitty`. List all nodes and edges.

---

## Step 2 — Identify Observable Node

Map the anomaly to a DAG node:

| Anomaly type            | Observable node in DAG         |
|------------------------|-------------------------------|
| ATA factor outlier      | `development_factor`          |
| Diagonal regression     | `calendar_year_effect`        |
| Paid vs incurred divergence | `claim_settlement_lag`   |
| Earned premium spike    | `exposure_volume`             |

---

## Step 3 — Do-Calculus Query

For the identified observable node, compute:

1. **Ancestors**: all nodes that can causally influence the observable node
2. **Backdoor paths**: paths from treatment variables to the observable that
   go through confounders
3. **Adjustment set**: minimal set of variables to condition on to identify
   the causal effect

Output:
```
Causal Trace — ATA outlier at Lag 2→3
  Observable node:   development_factor
  Direct causes:     claim_reporting_delay, reserve_strengthening,
                     large_loss_event, litigation_trend
  Backdoor paths:    3 paths found
  Adjustment set:    {accident_year, earned_premium}
```

---

## Step 4 — Score Pathways

For each direct cause, score plausibility based on:
- Magnitude of the Z-score (higher Z → more extreme event)
- Calendar year context (1988–1997 macro environment)
- LOB-specific knowledge (WC: occupational disease, repetitive stress)
- Cross-company signal (is anomaly isolated to one company or systemic?)

```
Pathway Scores (WC, Company 353, AY=1992, Lag=3)
  large_loss_event         0.72  ★ most plausible
  reserve_strengthening    0.61
  litigation_trend         0.44
  claim_reporting_delay    0.31
  data_error               0.18
```

---

## Step 5 — Write CCD

Write a Causal Context Document entry to `causal_context_docs`:

```sql
INSERT OR REPLACE INTO causal_context_docs
  (lob, grcode, accident_year, development_lag,
   dag_node, causal_pathway, adjustment_set,
   top_cause, plausibility_score, sha256, created_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP);
```

---

## Output Format

```
Causal Trace — LOB: WC, Company: 353, AY: 1992, Lag: 3
═══════════════════════════════════════════════════════
 DAG loaded              OK  (22 nodes, 31 edges)
 Observable node         development_factor
 Direct causes           4 identified
 Backdoor paths          3 found
 Adjustment set          {accident_year, earned_premium}
 Top causal pathway      large_loss_event (p=0.72)
 CCD written             OK  (sha256: a3f9…)
───────────────────────────────────────────────────────
 Status: COMPLETE
 Next:  /build-ccd WC grcode=353
        /draft-narrative WC grcode=353
```
