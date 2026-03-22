# Review Narrative — Agent 4: AI Narrative Generation

Display the most recent drafted narrative for a company+LOB, side-by-side
with the supporting anomaly flags and causal traces. Facilitates human
review before approval. Read-only — no API calls, no DB writes.

## Usage

```
/review-narrative <lob> grcode=<company> [version=<n>]
```

Examples:
```
/review-narrative WC grcode=353
/review-narrative WC grcode=353 version=2
```

Default: shows the most recent version.

---

## Step 1 — Load Narrative

```sql
SELECT *
FROM narrative_registry
WHERE lob = ? AND grcode = ?
ORDER BY version DESC
LIMIT 1;
```

If no narrative found: `ERROR — no narrative found. Run /draft-narrative first.`

---

## Step 2 — Load Supporting Evidence

Fetch supporting data to display alongside the narrative:

```sql
-- Anomaly flags
SELECT accident_year, development_lag, detector, z_score, flag_severity
FROM anomaly_flags
WHERE lob = ? AND grcode = ? AND detector = 'combined' AND is_flagged = 1
ORDER BY flag_severity DESC, accident_year;

-- Causal traces
SELECT accident_year, development_lag, top_cause, plausibility_score
FROM causal_context_docs
WHERE lob = ? AND grcode = ?
ORDER BY plausibility_score DESC;
```

---

## Step 3 — Display Review Package

```
═══════════════════════════════════════════════════════════════
 NARRATIVE REVIEW PACKAGE
 LOB: Workers Compensation | Company: 353 | Version: 1
 Generated: 2026-03-22  |  Model: claude-opus-4-6  |  Temp: 0
═══════════════════════════════════════════════════════════════

 SUPPORTING EVIDENCE
 ───────────────────────────────────────────────────────────────
 Anomaly Flags (8 total):
   AY=1992, Lag=3  CRITICAL  Z=3.14  →  top cause: large_loss_event (0.72)
   AY=1994, Lag=5  HIGH      Z=2.81  →  top cause: litigation_trend  (0.61)
   AY=1990, Lag=7  HIGH      Z=2.67  →  top cause: reserve_strengthening (0.58)
   ...

 GENERATED NARRATIVE
 ───────────────────────────────────────────────────────────────
 1. EXECUTIVE SUMMARY
    Workers Compensation development for Company 353 shows broadly stable
    patterns over the 1988–1997 period, with two material anomalies...

 2. KEY DEVELOPMENT OBSERVATIONS
    • Age-to-age factors at lags 1–3 are consistent with industry benchmarks
      (1.35–1.52), with the exception of AY 1992 lag 3 (ATA = 2.32)
    • Calendar year 1995 shows a diagonal effect across multiple companies,
      consistent with the litigation_trend → calendar_year_effect pathway
    ...

 3. ANOMALY ANALYSIS
    AY 1992, Lag 3 (CRITICAL):
    The ATA factor of 2.32 is 3.14 standard deviations above the mean.
    The causal trace identifies large_loss_event as the most plausible
    driver (plausibility = 0.72), consistent with a major occupational
    disease claim or serious injury emerging at the 3-year development mark...
    ...

 4. RESERVE ADEQUACY COMMENTARY
    ...

 5. LIMITATIONS AND CAVEATS
    ...

 ───────────────────────────────────────────────────────────────
 METADATA
   prompt_sha256:   b2c1a3…
   response_sha256: f8d4e2…
   tokens_used:     1,847
 ───────────────────────────────────────────────────────────────

 REVIEW ACTIONS
   /flag-for-approval WC grcode=353      ← approve for use
   /draft-narrative WC grcode=353        ← regenerate (creates version 2)
═══════════════════════════════════════════════════════════════
```

---

## Notes

- This command is **read-only** — no DB writes, no API calls
- Displays SHA-256 hashes for auditability (regulatory requirement)
- To approve the narrative, use `/flag-for-approval`
- To regenerate, run `/draft-narrative` again (a new version is created, old versions preserved)
