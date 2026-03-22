# Reset Pipeline — AXIOM-P&C Pipeline

Destructively clear all pipeline data for a given LOB (or all LOBs) and
reset back to an empty state. Use when you need a clean-room re-run, e.g.
after a source data correction.

**WARNING: This is irreversible. All triangles, flags, CCDs, and narratives
for the affected LOB will be permanently deleted.**

## Usage

```
/reset-pipeline lob=<lob> [confirm=true]
```

Examples:
```
/reset-pipeline lob=WC
/reset-pipeline lob=WC confirm=true
```

There is no "reset all LOBs" shortcut — each LOB must be reset individually
to prevent accidental data loss.

---

## Pre-conditions

- Must provide `lob` parameter — cannot reset without specifying a LOB
- Must confirm interactively (or pass `confirm=true`)
- Approved narratives add an extra confirmation step

---

## Step 1 — Safety Check: Approved Narratives

Query for approved narratives:

```sql
SELECT COUNT(*) FROM narrative_registry
WHERE lob = ? AND approved = 1;
```

If any approved narratives exist, issue a strong warning:

```
⚠  WARNING: APPROVED NARRATIVES WILL BE DELETED
══════════════════════════════════════════════════════════
 LOB WC has 3 APPROVED narratives.
 These have been reviewed and signed off by human actuaries.

 Deleting approved narratives requires a second confirmation.
 Type the LOB name to confirm: [____]
══════════════════════════════════════════════════════════
```

---

## Step 2 — Confirmation Prompt

```
RESET PIPELINE — LOB: WC
══════════════════════════════════════════════════════════
 The following data will be PERMANENTLY DELETED:

   triangles              840 rows
   ata_factors             90 rows
   anomaly_flags          420 rows
   causal_context_docs     82 rows
   narrative_registry      10 rows  (3 approved!)
   inst/ccd/wc_*.xml       10 files

 This action CANNOT be undone.
 The audit_log will be preserved.

 Are you sure you want to reset LOB WC? [y/N]
══════════════════════════════════════════════════════════
```

If not confirmed, abort with: `Reset cancelled. No data was deleted.`

---

## Step 3 — Execute Deletions

```sql
DELETE FROM triangles             WHERE lob = ?;
DELETE FROM ata_factors           WHERE lob = ?;
DELETE FROM anomaly_flags         WHERE lob = ?;
DELETE FROM causal_context_docs   WHERE lob = ?;
DELETE FROM narrative_registry    WHERE lob = ?;
```

Also delete CCD XML files: `inst/ccd/<lob>_*.xml`

---

## Step 4 — Audit Log

Even after reset, the audit log records the event:

```
event:   pipeline_reset
lob:     WC
rows_deleted:
  triangles: 840
  ata_factors: 90
  anomaly_flags: 420
  causal_context_docs: 82
  narrative_registry: 10
files_deleted: 10
reset_by: <current user>
ts:      <ISO-8601 timestamp>
```

---

## Output Format

```
Reset Pipeline — LOB: WC
═══════════════════════════════════════════
 triangles deleted         840  ✓
 ata_factors deleted         90  ✓
 anomaly_flags deleted      420  ✓
 causal_context_docs deleted  82  ✓
 narrative_registry deleted   10  ✓
 CCD XML files deleted        10  ✓
 Audit log entry              OK  ✓
───────────────────────────────────────────
 Status: RESET COMPLETE — LOB WC is now empty
 Next:  /run-pipeline lob=WC
```
