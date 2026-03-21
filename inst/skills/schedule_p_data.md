# Skill: CAS Schedule P Data Loading

## Overview

The CAS (Casualty Actuarial Society) Schedule P dataset contains loss development
triangles for U.S. property-casualty insurers, sourced from NAIC Schedule P filings.
It covers **accident years 1998–2007** with **10 years of development** per accident year.
The data was compiled by Glenn G. Meyers and Peng Shi.

This skill describes how to download, parse, and load the raw CAS CSV files for
**one line of business** into the internal SQLite schema, focusing on a single
NAIC insurer group to produce a clean 10×10 development triangle.

---

## Data Source

**Landing page:**
<https://www.casact.org/publications-research/research/research-resources/loss-reserving-data-pulled-naic-schedule-p>

**Direct CSV download URLs:**

| Line of Business           | Internal LOB | File                                                                               |
|----------------------------|:------------:|------------------------------------------------------------------------------------|
| Workers' Compensation      | `WC`         | `https://www.casact.org/sites/default/files/2021-04/wkcomp_pos.csv`               |
| Other Liability – Occurrence (GL) | `OL`  | `https://www.casact.org/sites/default/files/2021-04/othliab_pos.csv`              |
| Products Liability – Occurrence   | `PL`  | `https://www.casact.org/sites/default/files/2021-04/prodliab_pos.csv`             |
| Commercial Auto            | `CA`         | `https://www.casact.org/sites/default/files/2021-04/comauto_pos.csv`              |
| Private Passenger Auto     | `PA`         | `https://www.casact.org/sites/default/files/2021-04/ppauto_pos.csv`               |
| Medical Malpractice – Occurrence  | `MM`  | `https://www.casact.org/sites/default/files/2021-04/medmal_pos.csv`               |

**Primary target for this app:** `OL` (GL Occurrence / Other Liability – Occurrence)
using `othliab_pos.csv`.

---

## Raw CAS CSV Schema

Both `wkcomp_pos.csv` and `othliab_pos.csv` share this structure (13 columns).
The loss/premium column names carry a **LOB-specific suffix**:

| Column                   | WC suffix | OL suffix | Type    | Description                                               |
|--------------------------|:---------:|:---------:|---------|-----------------------------------------------------------|
| `GRCODE`                 | —         | —         | integer | NAIC company group code (unique insurer identifier)       |
| `GRNAME`                 | —         | —         | char    | NAIC company group name                                   |
| `AccidentYear`           | —         | —         | integer | Accident year (1998–2007)                                 |
| `DevelopmentYear`        | —         | —         | integer | Calendar year of development                              |
| `DevelopmentLag`         | —         | —         | integer | Development lag = DevelopmentYear − AccidentYear + 1 (1–10) |
| `IncurLoss_{sfx}`        | `_D`      | `_h1`     | numeric | Cumulative incurred losses + ALAE at year end (USD 000s)  |
| `CumPaidLoss_{sfx}`      | `_D`      | `_h1`     | numeric | Cumulative paid losses + ALAE at year end (USD 000s)      |
| `BulkLoss_{sfx}`         | `_D`      | `_h1`     | numeric | Bulk & IBNR reserves at year end (USD 000s)               |
| `EarnedPremDIR_{sfx}`    | `_D`      | `_h1`     | numeric | Earned premium – direct and assumed (USD 000s)            |
| `EarnedPremCeded_{sfx}`  | `_D`      | `_h1`     | numeric | Earned premium – ceded (USD 000s)                         |
| `EarnedPremNet_{sfx}`    | `_D`      | `_h1`     | numeric | Earned premium – net of reinsurance (USD 000s)            |
| `Single`                 | —         | —         | integer | 1 = single entity; 0 = insurer group                      |
| `PostedReserve97_{sfx}`  | `_D`      | `_h1`     | numeric | Posted reserves in year 2007 (USD 000s)                   |

---

## Column Mapping: Raw CAS → Internal Schema

The internal `triangles` table uses this simplified schema:

| Internal column             | Source column(s)           | Notes                                    |
|-----------------------------|----------------------------|------------------------------------------|
| `lob`                       | hard-coded (`"OL"`, `"WC"`)| Set from the LOB being loaded            |
| `grcode`                    | `GRCODE`                   | Added to schema to support per-company   |
| `accident_year`             | `AccidentYear`             | Direct mapping                           |
| `development_lag`           | `DevelopmentLag`           | Direct mapping                           |
| `cumulative_paid_loss`      | `CumPaidLoss_{sfx}`        | Net paid losses (USD thousands)          |
| `cumulative_incurred_loss`  | `IncurLoss_{sfx}`          | Net incurred losses (USD thousands)      |
| `earned_premium`            | `EarnedPremNet_{sfx}`      | Net earned premium (USD thousands)       |

---

## Company Selection Strategy

The raw file contains ~150–200 NAIC company groups per LOB. For causal analysis
we work with **one company at a time** to get a coherent 10×10 triangle.

**Inclusion criteria for a usable company:**
1. At least 10 distinct accident years in the data
2. Complete upper triangle: DevelopmentLag ≤ (2007 − AccidentYear + 1) for all rows
3. Non-zero net earned premium for all accident years
4. `EarnedPremNet_{sfx}` > 0 across all rows

**Selection strategies** (configured via `company_strategy` argument):
- `"largest_premium"` — pick the company with the highest total net earned premium
  (default; largest companies have most stable, well-understood loss patterns)
- `"grcode"` — specify an explicit GRCODE (e.g., `grcode = 337`  for Travelers)
- `"most_complete"` — pick the company with the most complete triangle rows

---

## R Functions

All functions are in `R/layer_1_data/load_schedule_p_raw.R`.

### `lob_metadata(lob_code)`
Returns a named list with `url`, `col_suffix`, `filename` for the given LOB code.
Supported codes: `"OL"`, `"WC"`, `"PL"`, `"CA"`, `"PA"`, `"MM"`.

### `download_cas_csv(lob_code, dest_dir, force = FALSE)`
Downloads the raw CAS CSV for one LOB to `dest_dir/`. Returns the local file path.
Set `force = TRUE` to re-download even if file exists.

### `parse_cas_csv(file_path, lob_code)`
Reads the raw CAS CSV and returns a tidy data.frame with columns:
`lob`, `grcode`, `grname`, `accident_year`, `development_lag`,
`cumulative_paid_loss`, `cumulative_incurred_loss`, `earned_premium`.

### `select_company(df, grcode = NULL, strategy = "largest_premium")`
Filters a parsed data.frame to one company. Returns filtered data.frame plus
`attr(result, "company")` containing `grcode` and `grname`.

### `load_schedule_p_lob(lob_code, dest_dir, db_path, grcode = NULL, strategy = "largest_premium", force_download = FALSE)`
Full end-to-end loader:
1. Downloads CSV if not present
2. Parses raw columns
3. Selects one company
4. Upserts into the `triangles` SQLite table
5. Computes and upserts ATA factors

Returns an invisible list: `list(grcode, grname, n_triangle_rows, n_ata_rows)`.

---

## Usage Examples

```r
# Load GL Occurrence for the largest company (default)
source("R/layer_1_data/load_schedule_p_raw.R")
result <- load_schedule_p_lob(
  lob_code     = "OL",
  dest_dir     = "data/schedule_p",
  db_path      = "data/database/reserving.db"
)
message("Loaded: ", result$grname, " (GRCODE=", result$grcode, ")")

# Load Workers Comp for a specific company (Travelers, GRCODE=337)
result <- load_schedule_p_lob(
  lob_code  = "WC",
  dest_dir  = "data/schedule_p",
  db_path   = "data/database/reserving.db",
  grcode    = 337
)

# Force re-download and load
result <- load_schedule_p_lob(
  lob_code        = "OL",
  dest_dir        = "data/schedule_p",
  db_path         = "data/database/reserving.db",
  force_download  = TRUE
)

# Inspect the triangle after loading
con <- DBI::dbConnect(RSQLite::SQLite(), "data/database/reserving.db")
tri <- DBI::dbGetQuery(con, "SELECT * FROM triangles WHERE lob = 'OL' ORDER BY accident_year, development_lag")
DBI::dbDisconnect(con)
```

---

## Data Quality Notes

- **Upper triangle only:** Raw files contain the full run-off (upper + lower triangle).
  The `parse_cas_csv()` function returns all rows; callers should filter to the upper
  triangle (`development_lag <= 2007 - accident_year + 1`) for modelling.
- **Currency:** All monetary amounts are in USD thousands (000s).
- **Accident years:** 1998–2007 (10 years), development lags 1–10.
- **No missing lags:** Any company passing the selection criteria has complete rows
  for all (AccidentYear, DevelopmentLag) combinations in the upper triangle.
- **ALAE included:** Paid and incurred losses include allocated loss adjustment
  expenses (ALAE), consistent with NAIC Schedule P definitions.
