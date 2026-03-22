# Scan Anomalies — Agent 2: Anomaly Detection

Run all anomaly detectors over a triangles LOB and write results to the
`anomaly_flags` table. Combines Z-score and diagonal regression signals.

## Usage

```
/scan-anomalies <lob> [grcode=<company>] [z_threshold=2.5]
```

Examples:
```
/scan-anomalies WC
/scan-anomalies WC grcode=353
/scan-anomalies WC z_threshold=3.0
```

Default Z-score threshold: **2.5**

---

## Pre-conditions

The `triangles` table must have rows for the requested LOB.
If empty, stop with: `ERROR — no triangles found for LOB <lob>. Run /ingest-lob first.`

---

## Step 1 — Z-Score Detector

For each `(lob, grcode, development_lag)`:

1. Collect the series of ATA factors across accident years (from `ata_factors`)
2. Compute mean and SD for the series
3. For each ATA factor, compute `z = (ata - mean) / sd`
4. Flag if `|z| > z_threshold`

Insert flags:
```sql
INSERT OR REPLACE INTO anomaly_flags
  (lob, grcode, accident_year, development_lag,
   detector, z_score, is_flagged, flag_severity, created_at)
VALUES (?, ?, ?, ?, 'zscore', ?, ?, ?, CURRENT_TIMESTAMP);
```

Severity scale:
- `|z|` 2.5–3.0 → `WARN`
- `|z|` 3.0–4.0 → `HIGH`
- `|z|` > 4.0   → `CRITICAL`

---

## Step 2 — Diagonal Regression Detector

For each `(lob, grcode, development_lag)`, fit:

```
cumulative_paid ~ accident_year
```

using data from the `triangles` table. Compute the residual for each cell.
Standardise residuals. Flag cells with `|std_resid| > z_threshold`.

Insert flags with `detector = 'diagonal_regression'`.

---

## Step 3 — Combine Signals

For each `(grcode, accident_year, development_lag)`, produce a combined flag:

```
combined_flagged = zscore_flagged OR diagonal_flagged
combined_severity = MAX(zscore_severity, diagonal_severity)
```

Insert combined rows with `detector = 'combined'`.

---

## Step 4 — Audit Log

```
event:   layer2_scan_complete
lob:     WC
grcode:  ALL
flags_written:  42
critical: 3
high:     12
warn:     27
ts:      <ISO-8601 timestamp>
```

---

## Output Format

```
Anomaly Scan — LOB: WC
═══════════════════════════════════════════
 Z-score detector        DONE  38 flags written
 Diagonal regression      DONE  31 flags written
 Combined signal          DONE  42 unique cells flagged
───────────────────────────────────────────
 Severity breakdown:
   CRITICAL  3
   HIGH      12
   WARN      27
───────────────────────────────────────────
 Status: COMPLETE
 Next:  /trace-anomaly WC  (for causal context)
        /explain-flag WC grcode=353 accident_year=1992 development_lag=3
```
