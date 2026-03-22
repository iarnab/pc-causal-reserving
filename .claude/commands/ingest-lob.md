# Ingest LOB — Agent 1: Data Ingestion

Ingest one line of business from a validated Schedule P file into the
SQLite database. Builds the loss triangle and computes ATA factors.

## Usage

```
/ingest-lob <lob> [file=<path>]
```

Examples:
```
/ingest-lob WC
/ingest-lob WC file=data-raw/cas_schedule_p.csv
```

Supported LOBs: `WC`, `OL`, `PL`, `CA`, `PA`, `MM`

---

## Pre-conditions

1. Run `/validate-input` first. Do NOT proceed if validation returned FAIL.
2. Confirm the SQLite database exists at `data/database/causal_reserving.db`.
   If not, call `layer1_ingest_schedule_p::init_schema()` first.

---

## Steps

### Step 1 — Filter Source Data

From the validated CSV/Excel, select only rows where `lob == <lob>`.
Log the row count.

### Step 2 — Upsert Triangle Rows

For each row insert into the `triangles` table using `INSERT OR REPLACE`:

```sql
INSERT OR REPLACE INTO triangles
  (lob, grcode, accident_year, development_lag,
   cumulative_paid, cumulative_incurred, earned_premium)
VALUES (?, ?, ?, ?, ?, ?, ?);
```

All writes are idempotent — re-running produces the same result.

### Step 3 — Compute ATA Factors

After upsert, call `layer1_compute_ata_factors(<lob>)` which:
- Groups by `(lob, grcode, development_lag)`
- Computes `ata = cumulative_paid[lag+1] / cumulative_paid[lag]`
- Inserts into `ata_factors` table (`INSERT OR REPLACE`)

### Step 4 — Verify

Query the DB and confirm:
```sql
SELECT COUNT(*) FROM triangles WHERE lob = ?;
SELECT COUNT(*) FROM ata_factors WHERE lob = ?;
```

Expected: triangles ≈ rows ingested, ata_factors = companies × (lags - 1).

### Step 5 — Audit Log

Append to `audit_log`:
```
event:   layer1_ingest_complete
lob:     WC
rows:    840
ata_rows: 90
ts:      <ISO-8601 timestamp>
```

---

## Output Format

```
Ingesting LOB: WC
═══════════════════════════════════════════
 Source rows found     840
 Rows upserted         840  ✓
 ATA factors computed   90  ✓
 Audit log entry        OK  ✓
───────────────────────────────────────────
 Status: COMPLETE — WC triangles ready
 Next:   /scan-anomalies WC
```

If any step fails, report the error and do NOT proceed to next steps.
Rollback guidance: re-run is safe (idempotent writes).
