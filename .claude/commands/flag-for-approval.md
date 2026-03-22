# Flag for Approval — Agent 4: AI Narrative Generation

Mark a reviewed narrative as approved for use in the reserve report.
Records the approval decision, approver identity, and timestamp in the
`audit_log` and `narrative_registry` tables.

## Usage

```
/flag-for-approval <lob> grcode=<company> [version=<n>] [approver=<name>]
```

Examples:
```
/flag-for-approval WC grcode=353
/flag-for-approval WC grcode=353 version=2 approver="J.Smith"
```

Default: approves the most recent version.

---

## Pre-conditions

1. A narrative must exist in `narrative_registry` for this company+LOB.
   If none: `ERROR — no narrative found. Run /draft-narrative first.`
2. Recommended: run `/review-narrative` before approving.

---

## Step 1 — Confirm Before Writing

Display a confirmation prompt:

```
APPROVAL CONFIRMATION
══════════════════════════════════════════════════════════
 You are about to APPROVE the following narrative:

   LOB:      Workers Compensation
   Company:  353
   Version:  1
   Created:  2026-03-22T14:23:00Z
   Model:    claude-opus-4-6
   Tokens:   1,847
   SHA-256:  f8d4e2…

 Approver: J.Smith
 Date:     2026-03-22

 This action will be recorded in the audit_log and cannot be undone.
 The narrative will be marked as approved and eligible for inclusion
 in the reserve report.

 Proceed? [y/N]
══════════════════════════════════════════════════════════
```

If the user does not confirm, stop without writing.

---

## Step 2 — Write Approval to DB

Update `narrative_registry`:

```sql
UPDATE narrative_registry
SET
  approved        = 1,
  approved_by     = ?,
  approved_at     = CURRENT_TIMESTAMP
WHERE lob = ? AND grcode = ? AND version = ?;
```

---

## Step 3 — Audit Log

```sql
INSERT INTO audit_log (event, lob, grcode, version, approved_by, ts)
VALUES ('layer4_narrative_approved', ?, ?, ?, ?, CURRENT_TIMESTAMP);
```

Audit entry:
```
event:       layer4_narrative_approved
lob:         WC
grcode:      353
version:     1
approved_by: J.Smith
sha256:      f8d4e2…
ts:          2026-03-22T14:31:00Z
```

---

## Step 4 — RLHF Feedback Prompt (Optional)

After approval, prompt for structured RLHF feedback to improve future
narrative quality:

```
OPTIONAL: RLHF Feedback (press Enter to skip)
──────────────────────────────────────────────
 Rate the narrative quality (1–5):
   Accuracy:      [_]
   Clarity:       [_]
   Causal grounding: [_]

 Any corrections or improvements? (free text):
   [_____________________________________________]
```

If feedback is provided, insert into `rlhf_feedback` table.

---

## Output Format

```
Flag for Approval — LOB: WC, Company: 353
═══════════════════════════════════════════
 Narrative v1            APPROVED  ✓
 Approved by             J.Smith
 Approved at             2026-03-22T14:31:00Z
 Audit log               OK  ✓
───────────────────────────────────────────
 Status: APPROVED — narrative eligible for reserve report
 Next:  /system-card-report    ← update KPMG System Card scores
        /audit-trail WC        ← review full audit trail
```
