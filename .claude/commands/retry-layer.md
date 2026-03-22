# Retry Layer — Agent 5: Orchestrator

Re-run a specific pipeline layer for a given LOB (and optionally company),
starting from a clean state for that layer. All layers below the specified
layer are preserved. Idempotent — safe to run multiple times.

## Usage

```
/retry-layer <layer> lob=<lob> [grcode=<company>]
```

Examples:
```
/retry-layer 3 lob=WC
/retry-layer 4 lob=WC grcode=353
/retry-layer 2 lob=OL
```

Valid layers: `1`, `2`, `3`, `4`, `5`

---

## Pre-conditions

The layer below the requested layer must be complete:
- Retry Layer 2 requires Layer 1 complete
- Retry Layer 3 requires Layer 2 complete
- Retry Layer 4 requires Layer 3 complete
- Retry Layer 5 requires Layer 4 complete

If the prerequisite layer is not complete:
```
ERROR — Cannot retry Layer 3: Layer 2 is not complete for LOB WC.
Run /run-pipeline lob=WC from_layer=2 first.
```

---

## Step 1 — Confirm Before Clearing

Display what will be cleared:

```
RETRY CONFIRMATION
══════════════════════════════════════════════════════════
 Retrying Layer 3 (Causal Reasoning) for LOB: WC

 The following data will be CLEARED before retry:
   causal_context_docs  WHERE lob = 'WC'   →  deleted
   inst/ccd/wc_*.xml                        →  deleted

 Layers 1–2 are preserved.
 Layer 4 (narratives) will be INVALIDATED if Layer 3 is re-run,
 because CCDs will change. You will need to re-run /draft-narrative.

 Proceed? [y/N]
══════════════════════════════════════════════════════════
```

---

## Step 2 — Clear Layer Data

Execute the appropriate DELETE statements for the target layer:

| Layer | Tables/files cleared |
|-------|---------------------|
| 1 | `triangles`, `ata_factors` for the LOB |
| 2 | `anomaly_flags` for the LOB |
| 3 | `causal_context_docs` for the LOB; `inst/ccd/<lob>_*.xml` |
| 4 | `narrative_registry` for the LOB |
| 5 | System Card metrics for the LOB |

Also cascade: clearing Layer N automatically marks Layers N+1 through 5
as invalidated in `audit_log`.

---

## Step 3 — Re-Run Layer

Execute the layer R function:

| Layer | R call |
|-------|--------|
| 1 | `layer1_ingest_schedule_p(lob)` + `layer1_compute_ata_factors(lob)` |
| 2 | `layer2_scan_anomalies(lob)` |
| 3 | `layer3_trace_anomaly(lob)` + `layer3_build_ccd(lob)` (per company) |
| 4 | `layer4_draft_narrative(lob)` (per company, uses Claude API) |
| 5 | `layer5_update_system_card_metrics(lob)` |

---

## Step 4 — Verify

Run the same gate checks as `/run-pipeline`:
- Row counts in expected tables > 0
- No errors in `audit_log` for this layer

---

## Step 5 — Audit Log

```
event:   layer<N>_retry
lob:     WC
grcode:  ALL
cleared: causal_context_docs (82 rows), inst/ccd/ (10 files)
result:  SUCCESS
ts:      <ISO-8601 timestamp>
```

---

## Output Format

```
Retry Layer 3 — LOB: WC
═══════════════════════════════════════════════════════
 Data cleared            causal_context_docs (82 rows)
                         inst/ccd/ (10 XML files)
 Layer 3 re-running      ...
 Causal traces           82 written  ✓
 CCDs built              10 written  ✓
 Audit log               OK
───────────────────────────────────────────────────────
 Status: COMPLETE
 NOTE: Layer 4 narratives are now stale. Re-run:
   /run-pipeline lob=WC from_layer=4
═══════════════════════════════════════════════════════
```
