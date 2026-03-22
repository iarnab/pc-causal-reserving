# Run Pipeline — Agent 5: Orchestrator

Execute the full AXIOM-P&C pipeline for one or more lines of business,
enforcing strict layer ordering (Layer N cannot start until Layer N-1
completes successfully).

## Usage

```
/run-pipeline [lob=<lob>] [grcode=<company>] [from_layer=<1-5>] [dry_run=true]
```

Examples:
```
/run-pipeline lob=WC                          ← full pipeline for WC
/run-pipeline lob=WC grcode=353               ← single company
/run-pipeline lob=WC from_layer=2             ← resume from Layer 2
/run-pipeline lob=WC dry_run=true             ← show plan, no execution
```

Supported LOBs: `WC`, `OL`, `PL`, `CA`, `PA`, `MM`
Default: runs all 10 companies for the specified LOB.

---

## Execution Plan

Before running, display the execution plan:

```
PIPELINE EXECUTION PLAN — LOB: WC
═══════════════════════════════════════════════════════════
 Layer 1  Data Ingestion        /ingest-lob WC
 Layer 2  Anomaly Detection     /scan-anomalies WC
 Layer 3  Causal Reasoning      /trace-anomaly WC + /build-ccd WC (per company)
 Layer 4  AI Narrative          /draft-narrative WC (per company)  [API calls]
 Layer 5  Observability         Update System Card scores
═══════════════════════════════════════════════════════════
 Companies:  10 (all)
 API calls:  10 (one narrative per company, Layer 4 only)
 Dry run:    NO
═══════════════════════════════════════════════════════════
Proceed? [y/N]
```

If `dry_run = TRUE`, stop here after showing the plan.

---

## Layer 1 — Data Ingestion

Call the Layer 1 pipeline:

```r
layer1_ingest_schedule_p(lob = lob)
layer1_compute_ata_factors(lob = lob)
```

Gate: Verify `SELECT COUNT(*) FROM triangles WHERE lob = ?` > 0.
If 0 rows: `FAIL — Layer 1 produced no triangle rows. Aborting.`

---

## Layer 2 — Anomaly Detection

```r
layer2_scan_anomalies(lob = lob, z_threshold = 2.5)
```

Gate: Verify `anomaly_flags` table has rows for the LOB.
If failure: `FAIL — Layer 2 produced no anomaly flags. Aborting.`

---

## Layer 3 — Causal Reasoning

For each company (grcode):
```r
layer3_trace_anomaly(lob = lob, grcode = grcode)
layer3_build_ccd(lob = lob, grcode = grcode)
```

Gate: Verify `causal_context_docs` has rows and CCD XML files exist.

---

## Layer 4 — AI Narrative

For each company (grcode):
```r
layer4_draft_narrative(lob = lob, grcode = grcode, temperature = 0)
```

Gate: Verify `narrative_registry` has rows for all companies.

Note: Layer 4 is the ONLY layer that calls the Anthropic API.

---

## Layer 5 — Observability

Update the KPMG System Card automated metrics:
```r
layer5_update_system_card_metrics(lob = lob)
```

---

## Progress Display

Show live progress as layers execute:

```
PIPELINE PROGRESS — LOB: WC
═══════════════════════════════════════════════════════════
 Layer 1  Data Ingestion       ████████████████  COMPLETE  (840 rows)
 Layer 2  Anomaly Detection    ████████████████  COMPLETE  (42 flags)
 Layer 3  Causal Reasoning     ████████████████  COMPLETE  (10 CCDs)
 Layer 4  AI Narrative         ████████░░░░░░░░  RUNNING   (4/10 companies)
 Layer 5  Observability        ░░░░░░░░░░░░░░░░  PENDING
═══════════════════════════════════════════════════════════
 Elapsed: 00:02:41  |  Estimated remaining: 00:01:35
```

---

## On Failure

If any layer fails, stop immediately and report:

```
PIPELINE FAILED — LOB: WC
═══════════════════════════════════════════════════════════
 Layer 1  COMPLETE
 Layer 2  COMPLETE
 Layer 3  FAILED — layer3_build_ccd(grcode=353): CCD XML write error
═══════════════════════════════════════════════════════════
 Error details: [error message]
 Completed layers are preserved in the DB.
 To retry from Layer 3:  /run-pipeline lob=WC from_layer=3
 To diagnose:            /pipeline-status lob=WC
```

---

## Final Summary

```
PIPELINE COMPLETE — LOB: WC
═══════════════════════════════════════════════════════════
 Layer 1  COMPLETE  840 triangle rows
 Layer 2  COMPLETE  42 anomaly flags
 Layer 3  COMPLETE  10 CCDs built
 Layer 4  COMPLETE  10 narratives drafted
 Layer 5  COMPLETE  System Card updated
───────────────────────────────────────────────────────────
 Total elapsed:   00:04:12
 API tokens used: 18,470
 Audit log:       OK
───────────────────────────────────────────────────────────
 Next:  /review-narrative WC grcode=353
        /pipeline-status lob=WC
        /system-card-report
═══════════════════════════════════════════════════════════
```
