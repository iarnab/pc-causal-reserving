# Tune Thresholds — Agent 2: Anomaly Detection

Interactively tune the Z-score and diagonal regression thresholds for a
given LOB to balance sensitivity vs. false-positive rate. Runs a dry-run
— does NOT write to the `anomaly_flags` table.

## Usage

```
/tune-thresholds <lob> [grcode=<company>]
```

Examples:
```
/tune-thresholds WC
/tune-thresholds WC grcode=353
```

---

## Step 1 — Compute Threshold Sensitivity Table

Run the Z-score and diagonal detectors across a grid of thresholds
(dry-run, no DB writes) and report flag counts:

| z_threshold | zscore_flags | diag_flags | combined_flags | critical | high | warn |
|-------------|-------------|------------|---------------|---------|------|------|
| 2.0         | 82          | 71         | 91            | 12      | 28   | 51   |
| 2.5 ★       | 38          | 31         | 42            |  3      | 12   | 27   |
| 3.0         | 18          | 14         | 21            |  2      |  7   | 12   |
| 3.5         |  7          |  5         |  9            |  1      |  3   |  5   |
| 4.0         |  2          |  2         |  3            |  0      |  1   |  2   |

★ = current default

---

## Step 2 — Distribution Statistics

Report the empirical distribution of Z-scores for the LOB:

```
Z-score distribution (LOB: WC, N=900 ATA factors)
  P50 (median):  0.12
  P75:           0.68
  P90:           1.34
  P95:           1.89
  P99:           2.71
  P99.9:         3.84
  Max observed:  4.22
```

---

## Step 3 — Flag Rate Guidance

Report what percentage of cells are flagged at each threshold:

```
z_threshold  flag_rate   interpretation
2.0          10.1%       Very sensitive — too many false positives
2.5           4.7%  ★    Recommended — balanced
3.0           2.3%       Conservative — may miss real anomalies
3.5           1.0%       Strict — only extreme outliers
```

Benchmark: CAS best-practice for reserving anomaly detection is 3–7%
flag rate per triangle.

---

## Step 4 — Recommendation

Provide a recommendation:

```
RECOMMENDATION
══════════════
LOB: WC — current threshold 2.5 produces 4.7% flag rate.
This is within the recommended 3–7% range.

If you want fewer flags: use z_threshold=3.0
If you want more coverage: use z_threshold=2.0

To apply:  /scan-anomalies WC z_threshold=3.0
```

---

## Notes

- This command is **read-only** — no DB writes
- Always run before changing the default threshold for production scans
- Results depend on current data in `triangles` and `ata_factors` tables
