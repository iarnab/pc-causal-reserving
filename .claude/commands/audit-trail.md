# Audit Trail — AXIOM-P&C Pipeline

Display the full audit trail from the `audit_log` table for a given LOB,
company, or time range. Read-only — no DB writes.

## Usage

```
/audit-trail [lob=<lob>] [grcode=<company>] [layer=<1-5>] [since=<date>] [limit=<n>]
```

Examples:
```
/audit-trail                               ← all recent events (last 50)
/audit-trail lob=WC
/audit-trail lob=WC grcode=353
/audit-trail layer=4
/audit-trail since=2026-03-01 limit=100
```

---

## Step 1 — Query audit_log

```sql
SELECT event, lob, grcode, detail, ts
FROM audit_log
WHERE 1=1
  AND (? IS NULL OR lob = ?)
  AND (? IS NULL OR grcode = ?)
  AND (? IS NULL OR ts >= ?)
ORDER BY ts DESC
LIMIT ?;
```

---

## Step 2 — Display Audit Trail

```
AUDIT TRAIL — LOB: WC | Company: 353
(Showing 23 events, most recent first)
═══════════════════════════════════════════════════════════════════════════
 Timestamp            Event                        Detail
───────────────────────────────────────────────────────────────────────────
 2026-03-22 14:31:00  layer4_narrative_approved    v1, approved_by=J.Smith
 2026-03-22 14:23:00  layer4_narrative_drafted     v1, 1847 tokens, temp=0
 2026-03-22 14:10:00  layer3_ccd_built             sha256=a3f9…, 8 traces
 2026-03-22 14:08:00  layer3_trace_anomaly         8 cells traced
 2026-03-22 13:55:00  layer2_scan_complete         42 flags (3 CRITICAL)
 2026-03-22 13:50:00  layer1_ingest_complete       840 rows, 90 ATA factors
 2026-03-22 13:48:00  layer1_schema_migrated       v3 → v3 (no-op)
═══════════════════════════════════════════════════════════════════════════
```

---

## Step 3 — Summary Statistics

Below the event list, show summary counts:

```
SUMMARY
────────────────────────────────────
 Total events logged:       23
 Layers run:                1, 2, 3, 4
 Last ingest:               2026-03-22 13:50:00
 Last narrative drafted:    2026-03-22 14:23:00
 Last approved:             2026-03-22 14:31:00  (J.Smith)
 Narratives awaiting review:  0
────────────────────────────────────
```

---

## Notes

- Read-only — no DB writes or API calls
- The `audit_log` table is append-only; events are never deleted
- For a high-level pipeline view, use `/pipeline-status`
- For KPMG System Card governance report, use `/system-card-report`
