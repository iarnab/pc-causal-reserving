# Validate Input — Agent 1: Data Ingestion

Validate a Schedule P CSV or Excel file against the expected schema
BEFORE ingesting it into the database. Read-only — no DB writes.

## Instructions

The user will provide a file path. If none is given, look for files
matching `data-raw/*.csv` or `data-raw/*.xlsx`.

---

## 1. File Existence

Check that the file exists and is readable. If not, stop with FAIL and
tell the user the exact path that was checked.

---

## 2. Column Schema Check

Load the first 5 rows using the filesystem MCP tool and verify these
required columns are present (exact names, case-sensitive):

| Column | Type | Notes |
|--------|------|-------|
| `lob` | string | Must be one of: WC, OL, PL, CA, PA, MM |
| `grcode` | integer | Company code |
| `accident_year` | integer | 1988–1997 |
| `development_lag` | integer | 1–10 |
| `cumulative_paid` | numeric | Must be ≥ 0 |
| `cumulative_incurred` | numeric | Must be ≥ 0 |
| `earned_premium` | numeric | Must be > 0 |

Report any missing columns as FAIL with a diff:
```
Missing:  earned_premium, cumulative_paid
Present:  lob, grcode, accident_year, development_lag, cumulative_incurred
```

---

## 3. LOB Values

Check that all values in the `lob` column are in the allowed set:
`WC`, `OL`, `PL`, `CA`, `PA`, `MM`

Report any unexpected values as WARN:
```
WARN: unexpected lob values found: ["GL", "AUTO"] — these rows will be skipped
```

---

## 4. Year Range

Check that `accident_year` values fall within 1988–1997.
Report out-of-range values as WARN with count.

---

## 5. Triangle Completeness Preview

For each LOB × company combination, count how many
(accident_year, development_lag) cells are present vs expected (10×10 = 100).

```
LOB  grcode  cells_present  cells_expected  pct_complete
WC   353      100            100             100%
WC   388       95            100              95%  ← WARN
```

Flag any combination below 80% as WARN.

---

## 6. Duplicate Key Check

Check for duplicate rows on the primary key:
`(lob, grcode, accident_year, development_lag)`

Report count of duplicates as WARN if > 0.

---

## Output Format

```
Schedule P Input Validation — <file_path>
═══════════════════════════════════════════
 File Exists          PASS
 Column Schema        PASS
 LOB Values           WARN  unexpected: ["GL"] — 42 rows
 Year Range           PASS
 Triangle Completeness WARN  3 companies below 80%
 Duplicate Keys       PASS
───────────────────────────────────────────
 Overall              WARN  — safe to ingest with warnings
 Rows checked:        8,400
 LOBs found:          WC, OL, PL
 Companies found:     10
```

If all PASS: `Overall: PASS — file ready for ingest_lob`.
If any FAIL: `Overall: FAIL — fix errors before ingesting`.
