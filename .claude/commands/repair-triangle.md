# Repair Triangle — Agent 1: Data Ingestion

Detect and repair structural gaps in a loss triangle already stored in
the database. Fills missing (accident_year × development_lag) cells using
a configurable imputation strategy.

## Usage

```
/repair-triangle <lob> [grcode=<company>] [method=<strategy>]
```

Examples:
```
/repair-triangle WC
/repair-triangle WC grcode=353
/repair-triangle WC grcode=353 method=geometric
```

Methods: `geometric` (default), `vwf` (volume-weighted factor), `zero`

---

## Step 1 — Identify Missing Cells

Query for expected vs actual cells:

```sql
-- expected: all 10×10 combinations per company
WITH expected AS (
  SELECT lob, grcode, a.y AS accident_year, d.l AS development_lag
  FROM (SELECT DISTINCT lob, grcode FROM triangles WHERE lob = ?) t
  CROSS JOIN (SELECT value AS y FROM generate_series(1988, 1997)) a
  CROSS JOIN (SELECT value AS l FROM generate_series(1, 10)) d
)
SELECT e.* FROM expected e
LEFT JOIN triangles t USING (lob, grcode, accident_year, development_lag)
WHERE t.cumulative_paid IS NULL;
```

If no missing cells: report `PASS — triangle complete, no repair needed` and stop.

---

## Step 2 — Diagnose Gap Pattern

Classify gaps by pattern:

| Pattern | Description | Recommended method |
|---------|-------------|-------------------|
| Upper-right | Future cells (lag > 10 - (1997 - acc_yr)) | Expected — skip |
| Random interior | Isolated missing cells | geometric |
| Full diagonal | Entire accident year missing | Escalate to user |
| Full column | Entire development lag missing | Escalate to user |

Do NOT attempt imputation for "full diagonal" or "full column" gaps —
report and ask user to re-check source data.

---

## Step 3 — Imputation

### `geometric` method (default)

For each missing interior cell `(ay, lag)`:

```
imputed = prior_cell × geometric_mean(ATA factors for this lag across other companies)
```

### `vwf` method

Use the volume-weighted average factor from `ata_factors` for the lag.

### `zero` method

Insert 0 for cumulative_paid and cumulative_incurred.
Set `imputed = TRUE` flag.

---

## Step 4 — Write Imputed Values

Insert with `INSERT OR REPLACE` and set `is_imputed = 1`:

```sql
INSERT OR REPLACE INTO triangles
  (lob, grcode, accident_year, development_lag,
   cumulative_paid, cumulative_incurred, earned_premium, is_imputed)
VALUES (?, ?, ?, ?, ?, ?, ?, 1);
```

---

## Step 5 — Audit Log

```
event:   layer1_triangle_repair
lob:     WC
grcode:  353
cells_repaired: 5
method:  geometric
ts:      <ISO-8601 timestamp>
```

---

## Output Format

```
Triangle Repair — LOB: WC, Company: 353
══════════════════════════════════════════
 Missing cells found    5
 Pattern               Interior gaps (safe to impute)
 Method                geometric
 Cells imputed         5  ✓
 Audit log             OK  ✓
──────────────────────────────────────────
 Status: REPAIRED — 5 cells imputed
 NOTE: Imputed cells are flagged (is_imputed=1) in DB
 Next:  Re-run /validate-input or proceed to /scan-anomalies
```
