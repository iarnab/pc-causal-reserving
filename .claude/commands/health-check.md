# Health Check — AXIOM-P&C Pipeline

Run a full environment and data health check across all 5 pipeline layers.
Report each item as PASS, WARN, or FAIL with a brief reason.

## Instructions

Work through each section below in order. Use the available MCP tools
(`sqlite`, `filesystem`) to gather facts. Do NOT run the pipeline — this
is read-only diagnostics only.

---

## 1. Environment

Check the following and mark PASS/FAIL:

- `.Renviron` exists at the repo root and contains `ANTHROPIC_API_KEY=`
  (check that the key is non-empty; do not print its value)
- `data/database/causal_reserving.db` exists on disk
- `inst/dag/reserving_dag.txt` exists and is non-empty
- `inst/validation_rules.yaml` exists and is non-empty

---

## 2. R Source Files

Verify these files exist in `R/` (Layer prefixes must match):

| Layer | Expected files |
|-------|---------------|
| 1 | `layer1_ingest_schedule_p.R`, `layer1_load_schedule_p_raw.R` |
| 2 | `layer2_detect_triangle_anomalies.R` |
| 3 | `layer3_build_reserving_dag.R`, `layer3_generate_ccd.R` |
| 4 | `layer4_claude_client.R`, `layer4_synthesize_reserve_narrative.R` |
| 5 | `layer5_system_card.R` |

Mark PASS if all files exist, FAIL with the missing filenames otherwise.

---

## 3. Database Schema

Query the SQLite DB and check that all required tables exist:

```sql
SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name;
```

Required tables: `triangles`, `ata_factors`, `anomaly_flags`,
`causal_context_docs`, `narrative_registry`, `audit_log`

Mark PASS if all 6 are present. For any missing table, mark FAIL.

---

## 4. Data Presence (Layer-by-Layer)

Run these row-count queries and report the numbers:

```sql
SELECT COUNT(*) AS n FROM triangles;
SELECT COUNT(*) AS n FROM ata_factors;
SELECT COUNT(*) AS n FROM anomaly_flags;
SELECT COUNT(*) AS n FROM causal_context_docs;
SELECT COUNT(*) AS n FROM narrative_registry;
```

- `triangles` = 0 → FAIL (pipeline has never been run)
- `triangles` > 0 but `ata_factors` = 0 → WARN (ingestion incomplete)
- `anomaly_flags` = 0 when `triangles` > 0 → WARN (Layer 2 not run)
- `causal_context_docs` = 0 when `anomaly_flags` > 0 → WARN (Layer 3 not run)
- `narrative_registry` = 0 when `causal_context_docs` > 0 → WARN (Layer 4 not run)

---

## 5. Audit Log — Last Run

Query the most recent 5 audit log entries:

```sql
SELECT layer, status, timestamp, details
FROM audit_log
ORDER BY timestamp DESC
LIMIT 5;
```

If the table is empty, report WARN (no pipeline runs recorded).
If the most recent entry has `status = 'error'`, report WARN with the layer number.

---

## 6. MCP Tools

Confirm the following MCP servers are registered in `.mcp.json`:
- `sqlite`
- `filesystem`
- `pipeline`

Mark PASS if all 3 keys exist in `.mcp.json`. Mark FAIL with missing names.

---

## Output Format

Print a final scorecard like this:

```
AXIOM-P&C Health Check — <date>
═══════════════════════════════════════
 Environment         PASS
 R Source Files      PASS
 DB Schema           PASS
 Data Presence       WARN  triangles=0 (pipeline not yet run)
 Audit Log           WARN  no entries
 MCP Tools           PASS
───────────────────────────────────────
 Overall             WARN  2 items need attention
```

If all 6 items are PASS, print `Overall: PASS — system ready`.
If any item is FAIL, print `Overall: FAIL — resolve before running pipeline`.
