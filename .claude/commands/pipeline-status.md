# Pipeline Status — Agent 5: Orchestrator

Show the current state of the pipeline for one or all LOBs: which layers
have completed, row counts for each DB table, and any pending work.
Read-only — no DB writes.

## Usage

```
/pipeline-status [lob=<lob>] [grcode=<company>]
```

Examples:
```
/pipeline-status                   ← all LOBs
/pipeline-status lob=WC
/pipeline-status lob=WC grcode=353
```

---

## Step 1 — Query DB Counts

Run count queries for each table, by LOB (and optionally grcode):

```sql
SELECT
  lob,
  (SELECT COUNT(*) FROM triangles       WHERE lob = t.lob) AS triangle_rows,
  (SELECT COUNT(*) FROM ata_factors     WHERE lob = t.lob) AS ata_rows,
  (SELECT COUNT(*) FROM anomaly_flags   WHERE lob = t.lob AND detector='combined' AND is_flagged=1) AS flags,
  (SELECT COUNT(*) FROM causal_context_docs WHERE lob = t.lob) AS ccd_traces,
  (SELECT COUNT(*) FROM narrative_registry  WHERE lob = t.lob) AS narratives,
  (SELECT COUNT(*) FROM narrative_registry  WHERE lob = t.lob AND approved=1) AS approved
FROM (SELECT DISTINCT lob FROM triangles) t;
```

---

## Step 2 — Derive Layer Status

Map row counts to layer status:

| Layer | COMPLETE condition |
|-------|-------------------|
| Layer 1 | `triangle_rows > 0 AND ata_rows > 0` |
| Layer 2 | `flags > 0` |
| Layer 3 | `ccd_traces > 0` |
| Layer 4 | `narratives >= companies_with_flags` |
| Layer 5 | `system_card_last_updated IS NOT NULL` |

---

## Step 3 — Display Status Report

```
PIPELINE STATUS — 2026-03-22
═══════════════════════════════════════════════════════════════════════
 LOB   Layer1      Layer2      Layer3      Layer4      Layer5   Approved
───────────────────────────────────────────────────────────────────────
 WC    ✓ 840 rows  ✓ 42 flags  ✓ 10 CCDs  ✓ 10 narr.  ✓       3/10
 OL    ✓ 780 rows  ✓ 38 flags  ✓ 10 CCDs  ✗ 0 narr.   ✗       0/10
 PL    ✗ 0 rows    ✗           ✗           ✗           ✗       0/10
═══════════════════════════════════════════════════════════════════════
 Legend: ✓ = complete  ✗ = not started or failed

 PENDING ACTIONS
 ───────────────────────────────────────────────────────────────────
 OL:  /draft-narrative OL (Layer 4 not run)
 PL:  /run-pipeline lob=PL (no data ingested)
 WC:  7 narratives awaiting approval — use /review-narrative WC
═══════════════════════════════════════════════════════════════════════
```

---

## Detailed Mode (single LOB+company)

When `lob` and `grcode` are both provided, show cell-level detail:

```
PIPELINE STATUS — LOB: WC, Company: 353
═══════════════════════════════════════════════════════════════
 Layer 1  Triangle rows:      100  ✓
          ATA factors:          9  ✓ (per lag, 9 lags)
          Imputed cells:         0

 Layer 2  Total flags:          8  ✓
          Critical:              1
          High:                  3
          Warn:                  4

 Layer 3  Causal traces:        8  ✓
          CCD file:     inst/ccd/wc_353.xml  ✓
          CCD sha256:   a3f9…

 Layer 4  Narrative version:    1  ✓
          Approved:             YES  (J.Smith, 2026-03-22)
          Model:        claude-opus-4-6
          Temperature:  0

 Layer 5  System Card updated:  2026-03-22T14:45:00Z  ✓
═══════════════════════════════════════════════════════════════
```

---

## Notes

- Read-only — no DB writes or API calls
- Use `/run-pipeline` to advance layers
- Use `/retry-layer` to re-run a specific failed layer
