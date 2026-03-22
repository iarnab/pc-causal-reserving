# Build CCD — Agent 3: Causal Reasoning

Build (or rebuild) the full Causal Context Document (CCD) XML for a
company+LOB, aggregating all causal traces into a single signed artifact.
Writes to `causal_context_docs` and emits an XML file.

## Usage

```
/build-ccd <lob> grcode=<company> [output=<path>]
```

Examples:
```
/build-ccd WC grcode=353
/build-ccd WC grcode=353 output=inst/ccd/wc_353.xml
```

Default output path: `inst/ccd/<lob>_<grcode>.xml`

---

## Pre-conditions

1. `causal_context_docs` must have trace rows for the company+LOB.
   If none: `ERROR — run /trace-anomaly <lob> grcode=<grcode> first.`
2. The DAG definition must exist at `inst/dag/reserving_dag.txt`.

---

## Step 1 — Gather Inputs

Query all causal traces for this company+LOB:

```sql
SELECT *
FROM causal_context_docs
WHERE lob = ? AND grcode = ?
ORDER BY accident_year, development_lag;
```

Also fetch summary statistics from `triangles` and `anomaly_flags`.

---

## Step 2 — Build XML Structure

Produce an XML document conforming to the CCD schema:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CausalContextDocument version="1.0"
  lob="WC" grcode="353" generated_at="2026-03-22T00:00:00Z">

  <DAGReference>
    <file>inst/dag/reserving_dag.txt</file>
    <sha256><!-- hash of DAG file --></sha256>
    <nodes>22</nodes>
    <edges>31</edges>
  </DAGReference>

  <TriangleSummary>
    <accident_years>1988–1997</accident_years>
    <development_lags>1–10</development_lags>
    <cells_total>100</cells_total>
    <cells_flagged>8</cells_flagged>
  </TriangleSummary>

  <CausalTraces>
    <Trace accident_year="1992" development_lag="3">
      <ObservableNode>development_factor</ObservableNode>
      <TopCause>large_loss_event</TopCause>
      <PlausibilityScore>0.72</PlausibilityScore>
      <AdjustmentSet>accident_year, earned_premium</AdjustmentSet>
      <Narrative><!-- from causal_context_docs --></Narrative>
    </Trace>
    <!-- one <Trace> per flagged cell -->
  </CausalTraces>

  <Signature>
    <sha256><!-- SHA-256 of this document content --></sha256>
    <signed_at>2026-03-22T00:00:00Z</signed_at>
  </Signature>

</CausalContextDocument>
```

---

## Step 3 — Compute SHA-256

Compute SHA-256 over the XML body (excluding the `<Signature>` element).
Insert the hash into `<Signature>` and also store in `causal_context_docs`.

---

## Step 4 — Write Output

Write the XML to `inst/ccd/<lob>_<grcode>.xml` (create directory if needed).

---

## Step 5 — Audit Log

```
event:   layer3_ccd_built
lob:     WC
grcode:  353
traces:  8
output:  inst/ccd/wc_353.xml
sha256:  a3f9…
ts:      <ISO-8601 timestamp>
```

---

## Output Format

```
Build CCD — LOB: WC, Company: 353
═══════════════════════════════════════════
 Causal traces loaded    8
 DAG reference           inst/dag/reserving_dag.txt (sha256: b2c1…)
 XML built               OK  (22 nodes, 8 traces)
 SHA-256 signed          a3f9…
 File written            inst/ccd/wc_353.xml
 Audit log               OK
───────────────────────────────────────────
 Status: COMPLETE
 Next:  /draft-narrative WC grcode=353
```
