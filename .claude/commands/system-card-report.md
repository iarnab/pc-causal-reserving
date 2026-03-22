# System Card Report — AXIOM-P&C Pipeline

Generate and display the KPMG Trusted AI System Card report, scoring the
pipeline across 5 governance pillars using a 70/30 automated/human
composite. Read-only — no API calls, no writes unless attestations change.

## Usage

```
/system-card-report [lob=<lob>] [attest=true]
```

Examples:
```
/system-card-report
/system-card-report lob=WC
/system-card-report attest=true     ← interactive attestation mode
```

---

## Step 1 — Compute Automated Metrics (70%)

Query the DB to compute automated scores for each pillar:

### Pillar 1: Data Integrity
```sql
-- imputed cell rate (lower = better)
SELECT AVG(is_imputed) FROM triangles WHERE lob = ?;
-- schema migration idempotency: checked via audit_log
-- source file hash consistency: verified against stored sha256
```
Score formula: `1 - imputed_rate` (max 1.0), penalised for hash mismatches.

### Pillar 2: Transparency
```sql
-- fraction of flagged cells with a causal trace
SELECT
  SUM(CASE WHEN c.lob IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*)
FROM anomaly_flags a
LEFT JOIN causal_context_docs c USING (lob, grcode, accident_year, development_lag)
WHERE a.lob = ? AND a.is_flagged = 1;
```

### Pillar 3: Explainability
```sql
-- fraction of narratives with anomaly_analysis section populated
SELECT AVG(CASE WHEN anomaly_analysis IS NOT NULL THEN 1 ELSE 0 END)
FROM narrative_registry WHERE lob = ?;
```

### Pillar 4: Accountability
```sql
-- fraction of narratives that have been approved
SELECT AVG(approved) FROM narrative_registry WHERE lob = ?;
-- audit_log completeness: every layer event present
```

### Pillar 5: Reliability
```sql
-- fraction of pipeline runs that completed all 5 layers without error
-- temperature = 0 compliance (from narrative_registry.temperature)
SELECT AVG(CASE WHEN temperature = 0 THEN 1 ELSE 0 END)
FROM narrative_registry WHERE lob = ?;
```

---

## Step 2 — Load Human Attestation Scores (30%)

```sql
SELECT pillar, attestation_score, attested_by, attested_at
FROM system_card_attestations
WHERE lob = ? OR lob IS NULL
ORDER BY attested_at DESC;
```

If no attestations exist for a pillar, use 0.5 as default (neutral).

---

## Step 3 — Compute Composite Scores

For each pillar:
```
composite = 0.70 × automated_score + 0.30 × attestation_score
```

---

## Step 4 — Display Report

```
╔═════════════════════════════════════════════════════════════════════╗
║         AXIOM-P&C KPMG TRUSTED AI SYSTEM CARD                      ║
║         LOB: Workers Compensation  |  Date: 2026-03-22              ║
╠═════════════════════════════════════════════════════════════════════╣
║ Pillar              Auto (70%)  Human (30%)  Composite  Status      ║
╠═════════════════════════════════════════════════════════════════════╣
║ Data Integrity         0.97        0.90         0.95    ✓ PASS      ║
║ Transparency           0.88        0.85         0.87    ✓ PASS      ║
║ Explainability         0.82        0.80         0.81    ✓ PASS      ║
║ Accountability         0.70        0.75         0.72    ✓ PASS      ║
║ Reliability            1.00        0.90         0.97    ✓ PASS      ║
╠═════════════════════════════════════════════════════════════════════╣
║ OVERALL COMPOSITE SCORE:                          0.86   ✓ PASS     ║
╠═════════════════════════════════════════════════════════════════════╣
║ Threshold: 0.70 (PASS)  |  Regulatory: CAS E-Forum, Solvency II    ║
╚═════════════════════════════════════════════════════════════════════╝

PILLAR NOTES
───────────────────────────────────────────────────────────────────────
 Data Integrity:   0 imputed cells, all source hashes verified
 Transparency:     88% of flagged cells have causal traces (target: 90%)
 Explainability:   82% of narratives have anomaly analysis section
 Accountability:   70% of narratives approved by human actuary
                   ⚠ 3 narratives pending approval — see /review-narrative
 Reliability:      All 10 narratives used temperature=0  ✓

ATTESTATIONS ON FILE
───────────────────────────────────────────────────────────────────────
 Data Integrity:   J.Smith  2026-03-20  (score: 0.90)
 Accountability:   J.Smith  2026-03-22  (score: 0.75)
 [Pillars 2, 3, 5: using defaults — run /system-card-report attest=true]

RECOMMENDED ACTIONS
───────────────────────────────────────────────────────────────────────
 1. Approve 3 pending narratives:  /review-narrative WC
 2. Increase causal trace coverage to 90%:  /trace-anomaly WC
 3. Submit attestations for pillars 2, 3, 5:  /system-card-report attest=true
───────────────────────────────────────────────────────────────────────
```

---

## Attestation Mode (`attest=true`)

When `attest=true`, prompt for human scores for each un-attested pillar:

```
ATTESTATION MODE — Pillar: Transparency
══════════════════════════════════════════
 Automated score:  0.88 (88% of flags have causal traces)

 Please rate your confidence in the TRANSPARENCY of this system (0.0–1.0):
 Consider: Are causal pathways clearly documented and accessible?
 Score: [___]

 Attesting as: [___]  (name)
══════════════════════════════════════════
```

Write attestation to `system_card_attestations` table.

---

## Notes

- Minimum passing composite score: **0.70** per pillar
- Full pillar definitions follow KPMG Trusted AI framework
- CAS E-Forum and Solvency II reproducibility requirement drives `temperature=0`
- Attestations are stored with name and timestamp for auditability
