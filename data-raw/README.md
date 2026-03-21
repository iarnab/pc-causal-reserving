# Data Directory

## Schedule P Triangles (`data/schedule_p/`)

Place raw CAS Schedule P CSV files here. Files are gitignored — do not commit data.

### Expected CSV Column Schema

| Column | Type | Description |
|--------|------|-------------|
| `lob` | character | Line of business code: `"WC"`, `"CMP"`, `"OL"`, `"CA"`, `"MM"` |
| `accident_year` | integer | Accident year (e.g. 1988–1997) |
| `development_lag` | integer | Development lag in years (1–10) |
| `cumulative_paid_loss` | numeric | Cumulative paid losses (USD thousands) |
| `cumulative_incurred_loss` | numeric | Cumulative incurred losses (USD thousands) |
| `earned_premium` | numeric | Earned premium for that accident year (USD thousands) |

### Download

Run the helper script to download public CAS Schedule P data:

```r
source("data/download_schedule_p.R")
```

This fetches the CAS Research Working Party Schedule P dataset (1988–1997, 10 LOBs).
Workers Compensation (`WC`) is the primary demo LOB.

## Database (`data/database/`)

SQLite database files are gitignored. The database is initialised automatically on first run:

```r
source("R/layer_1_data/ingest_schedule_p.R")
initialise_database("data/database/reserving.db")
```

### Tables

| Table | Description |
|-------|-------------|
| `triangles` | Long-format loss triangle data |
| `ata_factors` | Age-to-age factors by LOB, accident year, development period |
| `anomaly_flags` | Detected anomalies with severity and rule metadata |
| `causal_context_docs` | CCD registry: SHA-256 hash, LOB, accident year, generated_at |
| `narrative_registry` | LLM narratives and RLHF feedback |
| `audit_log` | All API calls with timestamps and prompt hashes |
