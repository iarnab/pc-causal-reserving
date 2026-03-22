# Draft Narrative — Agent 4: AI Narrative Generation

Generate an actuarial reserve narrative for a company+LOB using the Claude
API. Grounds the narrative in the CCD and anomaly flags stored in the DB.
Always calls Claude with `temperature = 0`.

## Usage

```
/draft-narrative <lob> grcode=<company> [dry_run=true]
```

Examples:
```
/draft-narrative WC grcode=353
/draft-narrative WC grcode=353 dry_run=true    ← no API call, shows prompt only
```

---

## Pre-conditions

1. CCD must exist: `causal_context_docs` must have rows for this company+LOB.
   If none: `ERROR — run /trace-anomaly and /build-ccd first.`
2. `ANTHROPIC_API_KEY` must be set in `.Renviron`.
3. Layer 4 is the ONLY layer permitted to call the Claude API.

---

## Step 1 — Assemble System Prompt

Build the system prompt by combining:

1. **Role definition**: Actuarial reserve analyst for WC line of business
2. **CCD content**: Load from `inst/ccd/<lob>_<grcode>.xml`
3. **Regulatory constraints**: CAS E-Forum standards; reproducibility requirement
4. **Output format spec**: Structured sections (see Step 4)

```
System prompt structure:
  [ROLE]
  You are an expert P&C actuarial analyst reviewing Workers Compensation
  loss development triangles for a CAS research paper. Your analysis must
  be grounded in causal structure, not just statistical patterns.

  [CCD CONTENT]
  <CausalContextDocument>... (full XML) ...</CausalContextDocument>

  [CONSTRAINTS]
  - Cite specific accident years and development lags when discussing anomalies
  - Distinguish correlation from causation — use the DAG pathways provided
  - Temperature = 0 is enforced for reproducibility
  - Do not speculate beyond what the data and DAG support
```

---

## Step 2 — Assemble User Prompt

Build the user prompt from DB state:

```
Summarise the loss development experience for:
  LOB: Workers Compensation
  Company: 353
  Accident years: 1988–1997
  Development lags: 1–10

Flagged anomalies (from anomaly_flags):
  AY=1992, Lag=3: Z=3.14 (CRITICAL) — top cause: large_loss_event (p=0.72)
  AY=1994, Lag=5: Z=2.81 (HIGH)     — top cause: litigation_trend (p=0.61)
  ...

Please provide:
  1. Executive Summary (2–3 sentences)
  2. Key Development Observations (bullet list)
  3. Anomaly Analysis (one paragraph per flagged cell, citing causal pathway)
  4. Reserve Adequacy Commentary
  5. Limitations and Caveats
```

---

## Step 3 — Call Claude API

```r
response <- layer4_call_claude(
  system_prompt = system_prompt,
  user_prompt   = user_prompt,
  temperature   = 0,          # REQUIRED — never change
  max_tokens    = 2000,
  model         = "claude-opus-4-6"
)
```

If `dry_run = TRUE`, print the assembled prompts and stop — do NOT call API.

---

## Step 4 — Parse and Store Narrative

Parse the response into sections and insert into `narrative_registry`:

```sql
INSERT OR REPLACE INTO narrative_registry
  (lob, grcode, version, executive_summary, key_observations,
   anomaly_analysis, reserve_commentary, limitations,
   model_id, temperature, prompt_sha256, response_sha256, created_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, CURRENT_TIMESTAMP);
```

---

## Step 5 — Audit Log

```
event:   layer4_narrative_drafted
lob:     WC
grcode:  353
version: 1
model:   claude-opus-4-6
temperature: 0
tokens_used: 1847
ts:      <ISO-8601 timestamp>
```

---

## Output Format

```
Draft Narrative — LOB: WC, Company: 353
═══════════════════════════════════════════
 CCD loaded              OK  (inst/ccd/wc_353.xml)
 System prompt           1,842 tokens
 User prompt               621 tokens
 Claude API call         COMPLETE (1,847 tokens generated)
 Narrative stored        narrative_registry v1  ✓
 Audit log               OK
───────────────────────────────────────────
 EXECUTIVE SUMMARY
 ─────────────────
 Workers Compensation development for Company 353 shows broadly stable
 patterns over the 1988–1997 period, with two material anomalies in
 accident years 1992 and 1994 that are consistent with large-loss events
 and emerging litigation trends respectively...

 [Full narrative continues — use /review-narrative WC grcode=353 to review]
───────────────────────────────────────────
 Status: COMPLETE
 Next:  /review-narrative WC grcode=353
```
