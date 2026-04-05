# Skill: CAS Schedule P Data Loading

## Overview

The CAS (Casualty Actuarial Society) Schedule P dataset contains loss development
triangles for U.S. property-casualty insurers, sourced from NAIC Schedule P filings.
Two vintages are available:

| Vintage    | Accident Years | Development Lags | Compiled by                              |
|------------|:--------------:|:----------------:|------------------------------------------|
| `extended` | 1998–2007      | 1–10             | CAS Reserve Research Working Group, 2026 |
| `original` | 1988–1997      | 1–10             | Glenn G. Meyers & Peng Shi, 2008         |

**Default is `extended` (1998–2007)** — the latest CAS data release.

---

## Data Source

**Landing page:**
<https://www.casact.org/publications-research/research/research-resources/loss-reserving-data-pulled-naic-schedule-p>

### Extended vintage (1998–2007) — current default

Base URL: `https://www.casact.org/sites/default/files/2026-04`

| Line of Business                   | Internal LOB | Cached filename         | Full URL                                                                                   |
|------------------------------------|:------------:|-------------------------|--------------------------------------------------------------------------------------------|
| Workers' Compensation              | `WC`         | `wkcomp_pos_ext.csv`    | `https://www.casact.org/sites/default/files/2026-04/wkcomp_pos.csv`                       |
| Other Liability – Occurrence (GL)  | `OL`         | `othliab_pos_ext.csv`   | `https://www.casact.org/sites/default/files/2026-04/othliab_pos.csv`                      |
| Products Liability – Occurrence    | `PL`         | `prodliab_pos_ext.csv`  | `https://www.casact.org/sites/default/files/2026-04/prodliab_pos.csv`                     |
| Commercial Auto                    | `CA`         | `comauto_pos_ext.csv`   | `https://www.casact.org/sites/default/files/2026-04/comauto_pos.csv`                      |
| Private Passenger Auto             | `PA`         | `ppauto_pos_ext.csv`    | `https://www.casact.org/sites/default/files/2026-04/ppauto_pos.csv`                       |
| Medical Malpractice – Occurrence   | `MM`         | `medmal_pos_ext.csv`    | `https://www.casact.org/sites/default/files/2026-04/medmal_pos.csv`                       |

> **Note:** If downloads fail, verify the base URL on the CAS landing page above.
> The date path (`2026-04`) reflects when CAS published the extended vintage.
> Update `CAS_BASE_EXTENDED` in `R/layer1_load_schedule_p_raw.R` if the URL changes.

### Original vintage (1988–1997) — Meyers & Shi legacy data

Base URL: `https://www.casact.org/sites/default/files/2021-04`

| Line of Business                   | Internal LOB | Cached filename      | Full URL                                                                               |
|------------------------------------|:------------:|----------------------|----------------------------------------------------------------------------------------|
| Workers' Compensation              | `WC`         | `wkcomp_pos.csv`     | `https://www.casact.org/sites/default/files/2021-04/wkcomp_pos.csv`                   |
| Other Liability – Occurrence (GL)  | `OL`         | `othliab_pos.csv`    | `https://www.casact.org/sites/default/files/2021-04/othliab_pos.csv`                  |
| Products Liability – Occurrence    | `PL`         | `prodliab_pos.csv`   | `https://www.casact.org/sites/default/files/2021-04/prodliab_pos.csv`                 |
| Commercial Auto                    | `CA`         | `comauto_pos.csv`    | `https://www.casact.org/sites/default/files/2021-04/comauto_pos.csv`                  |
| Private Passenger Auto             | `PA`         | `ppauto_pos.csv`     | `https://www.casact.org/sites/default/files/2021-04/ppauto_pos.csv`                   |
| Medical Malpractice – Occurrence   | `MM`         | `medmal_pos.csv`     | `https://www.casact.org/sites/default/files/2021-04/medmal_pos.csv`                   |

---

## Raw CAS CSV Schema

Both vintages share the same 13-column structure. The loss/premium column names
carry a **LOB-specific suffix**. The only schema difference between vintages is the
`PostedReserve` column name (`PostedReserve97` vs `PostedReserve07`); the three
columns we ingest are identical.

| Column                   | WC suffix | OL suffix | Type    | Description                                                |
|--------------------------|:---------:|:---------:|---------|------------------------------------------------------------|
| `GRCODE`                 | —         | —         | integer | NAIC company group code (unique insurer identifier)        |
| `GRNAME`                 | —         | —         | char    | NAIC company group name                                    |
| `AccidentYear`           | —         | —         | integer | Accident year (1998–2007 extended; 1988–1997 original)     |
| `DevelopmentYear`        | —         | —         | integer | Calendar year of development                               |
| `DevelopmentLag`         | —         | —         | integer | Development lag = DevelopmentYear − AccidentYear + 1 (1–10)|
| `IncurLoss_{sfx}`        | `_D`      | `_h1`     | numeric | Cumulative incurred losses + ALAE at year end (USD 000s)   |
| `CumPaidLoss_{sfx}`      | `_D`      | `_h1`     | numeric | Cumulative paid losses + ALAE at year end (USD 000s)       |
| `BulkLoss_{sfx}`         | `_D`      | `_h1`     | numeric | Bulk & IBNR reserves at year end (USD 000s)                |
| `EarnedPremDIR_{sfx}`    | `_D`      | `_h1`     | numeric | Earned premium – direct and assumed (USD 000s)             |
| `EarnedPremCeded_{sfx}`  | `_D`      | `_h1`     | numeric | Earned premium – ceded (USD 000s)                          |
| `EarnedPremNet_{sfx}`    | `_D`      | `_h1`     | numeric | Earned premium – net of reinsurance (USD 000s)             |
| `Single`                 | —         | —         | integer | 1 = single entity; 0 = insurer group                       |
| `PostedReserve07_{sfx}`  | `_D`      | `_h1`     | numeric | **Extended** — Posted reserves in year 2007 (USD 000s)     |
| `PostedReserve97_{sfx}`  | `_D`      | `_h1`     | numeric | **Original** — Posted reserves in year 1997 (USD 000s)     |

---

## Column Mapping: Raw CAS → Internal Schema

The internal `triangles` table uses this simplified schema:

| Internal column             | Source column(s)           | Notes                                       |
|-----------------------------|----------------------------|---------------------------------------------|
| `lob`                       | hard-coded (`"OL"`, `"WC"`)| Set from the LOB being loaded               |
| `grcode`                    | `GRCODE`                   | Added to schema to support per-company      |
| `accident_year`             | `AccidentYear`             | Direct mapping                              |
| `development_lag`           | `DevelopmentLag`           | Direct mapping                              |
| `cumulative_paid_loss`      | `CumPaidLoss_{sfx}`        | Net paid losses (USD thousands)             |
| `cumulative_incurred_loss`  | `IncurLoss_{sfx}`          | Net incurred losses (USD thousands)         |
| `earned_premium`            | `EarnedPremNet_{sfx}`      | Net earned premium (USD thousands)          |

---

## Company Selection Strategy

The raw file contains ~150–200 NAIC company groups per LOB. For causal analysis
we work with **one company at a time** to get a coherent 10×10 triangle.

**Inclusion criteria for a usable company:**
1. At least 10 distinct accident years in the data
2. Complete upper triangle: DevelopmentLag ≤ (AY_MAX − AccidentYear + 1) for all rows
3. Non-zero net earned premium for all accident years
4. `EarnedPremNet_{sfx}` > 0 across all rows

**Selection strategies** (configured via `strategy` argument):
- `"largest_premium"` — pick the company with the highest total net earned premium
  (default; largest companies have most stable, well-understood loss patterns)
- `"most_complete"` — pick the company with the most complete triangle rows
- Direct GRCODE — pass `grcode = <integer>` to pin a specific insurer

---

## R Functions

All functions are in `R/layer1_load_schedule_p_raw.R`.

### `lob_metadata(lob_code, vintage = "extended")`
Returns a named list with `url`, `col_suffix`, `filename`, `ay_min`, `ay_max`,
`vintage` for the given LOB code and vintage.

### `download_cas_csv(lob_code, dest_dir, force = FALSE, vintage = "extended")`
Downloads the raw CAS CSV for one LOB to `dest_dir/`. Returns the local file path.
Extended-vintage files are cached as `*_ext.csv` to avoid overwriting original files.

### `parse_cas_csv(file_path, lob_code, vintage = "extended")`
Reads the raw CAS CSV and returns a tidy data.frame with columns:
`lob`, `grcode`, `grname`, `accident_year`, `development_lag`,
`cumulative_paid_loss`, `cumulative_incurred_loss`, `earned_premium`.

### `select_company(df, grcode = NULL, strategy = "largest_premium")`
Filters a parsed data.frame to one company. Returns filtered data.frame plus
`attr(result, "company")` containing `grcode` and `grname`.

### `list_schedule_p_companies(lob_code, dest_dir, vintage = "extended")`
Downloads (if needed) and parses the CSV, then returns a data.frame of all
companies with ≥10 complete rows, sorted by total earned premium.

### `load_schedule_p_lob(lob_code, dest_dir, db_path, grcode = NULL, strategy = "largest_premium", force_download = FALSE, vintage = "extended")`
Full end-to-end loader:
1. Downloads CSV if not present
2. Parses raw columns
3. Selects one company
4. Upserts into the `triangles` SQLite table
5. Computes and upserts ATA factors

Returns an invisible list: `list(grcode, grname, lob, n_triangle_rows, n_ata_rows)`.

---

## Usage Examples

```r
# Load GL Occurrence for the largest company — extended vintage (default)
result <- load_schedule_p_lob(
  lob_code = "OL",
  dest_dir = "data/schedule_p",
  db_path  = "data/database/causal_reserving.db"
)
message("Loaded: ", result$grname, " (GRCODE=", result$grcode, ")")

# Load Workers Comp for a specific company (Travelers, GRCODE=337)
result <- load_schedule_p_lob(
  lob_code = "WC",
  dest_dir = "data/schedule_p",
  db_path  = "data/database/causal_reserving.db",
  grcode   = 337
)

# Use the original 1988–1997 Meyers & Shi data
result <- load_schedule_p_lob(
  lob_code = "OL",
  dest_dir = "data/schedule_p",
  db_path  = "data/database/causal_reserving.db",
  vintage  = "original"
)

# Force re-download (e.g. after CAS publishes corrected file)
result <- load_schedule_p_lob(
  lob_code        = "OL",
  dest_dir        = "data/schedule_p",
  db_path         = "data/database/causal_reserving.db",
  force_download  = TRUE
)

# Browse available companies before loading
comps <- list_schedule_p_companies("MM", "data/schedule_p")
head(comps)
# grcode  grname               n_rows  total_premium
# 337     Travelers Group       100    12_345_678

# Inspect the triangle after loading
con <- DBI::dbConnect(RSQLite::SQLite(), "data/database/causal_reserving.db")
tri <- DBI::dbGetQuery(con,
  "SELECT * FROM triangles WHERE lob = 'OL' ORDER BY accident_year, development_lag")
DBI::dbDisconnect(con)
```

---

## Updating the Extended Vintage Base URL

If the CAS re-hosts the 1998–2007 files at a new path, update the constant at
the top of `R/layer1_load_schedule_p_raw.R`:

```r
CAS_BASE_EXTENDED <- "https://www.casact.org/sites/default/files/2026-04"
#                                                                 ^^^^^^^ change this
```

Then call `load_schedule_p_lob(..., force_download = TRUE)` to re-fetch.

---

## Data Quality Notes

- **Upper triangle only:** Raw files contain the full run-off (upper + lower triangle).
  Filter to `development_lag <= AY_MAX − accident_year + 1` for modelling.
- **Currency:** All monetary amounts are in USD thousands (000s).
- **Extended vintage:** 1998–2007 (10 accident years), development lags 1–10.
- **Original vintage:** 1988–1997 (10 accident years), development lags 1–10.
- **No missing lags:** Any company passing selection criteria has complete rows
  for all (AccidentYear, DevelopmentLag) combinations in the upper triangle.
- **ALAE included:** Paid and incurred losses include allocated loss adjustment
  expenses (ALAE), consistent with NAIC Schedule P definitions.
