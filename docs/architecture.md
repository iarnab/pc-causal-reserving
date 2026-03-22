# AXIOM-P&C System Architecture

> Causal Intelligence for P&C Loss Reserving
> CAS 2026 RFP | R package: `actuarialcausalintelligence` v0.1.0

---

## Overview

AXIOM-P&C is a **5-layer R pipeline** that grounds LLM reserve narratives in
explicit causal structure (do-calculus + Causal Context Documents).

Instead of passing raw loss triangles directly to an LLM, the system:

1. Detects anomalies in Schedule P development data (ATA Z-scores, diagonal effects)
2. Traces those anomalies through a structured 5-layer causal DAG
3. Constructs a **Causal Context Document (CCD)** — a SHA-256-registered XML
   document encoding the active causal subgraph and do-calculus queries
4. Injects the CCD into a Claude API prompt to produce auditable,
   counterfactual-capable reserve narratives
5. Collects FCAS-credentialed actuary feedback via an RLHF Shiny dashboard

---

## Data Flow

```
Schedule P (CSV/Excel)
      │
      ▼
┌─────────────────────────────────────────────────────┐
│ Layer 1: Data Ingestion (R/layer_1_data/)           │
│  load_schedule_p_raw() → ingest_schedule_p()        │
│  parse_triangle_csv() → build_development_triangles()│
│  compute_ata_factors()                               │
│  SQLite: triangles, ata_factors                      │
└──────────────────────┬──────────────────────────────┘
                       │ SQLite
                       ▼
┌─────────────────────────────────────────────────────┐
│ Layer 2: Anomaly Detection (R/layer_2_anomaly/)     │
│  detect_ata_zscore() → detect_diagonal_effect()     │
│  combine_anomaly_signals()                           │
│  Thresholds: inst/validation_rules.yaml             │
│  SQLite: anomaly_flags                               │
└──────────────────────┬──────────────────────────────┘
                       │ SQLite
                       ▼
┌─────────────────────────────────────────────────────┐
│ Layer 3: Causal Reasoning (R/layer_3_causal/)       │
│  build_reserving_dag() → query_do_calculus()        │
│  get_dag_paths() → generate_ccd() → register_ccd() │
│  DAG spec: inst/dag/reserving_dag.txt               │
│  SQLite: causal_context_docs                         │
└──────────────────────┬──────────────────────────────┘
                       │ SQLite
                       ▼
┌─────────────────────────────────────────────────────┐
│ Layer 4: AI Synthesis (R/layer_4_ai/)               │
│  ONLY layer allowed to call external APIs            │
│  build_reserve_narrative_prompt() → call_claude()   │
│  synthesize_reserve_narrative() [temperature = 0]   │
│  SQLite: narrative_registry                          │
└──────────────────────┬──────────────────────────────┘
                       │ SQLite
                       ▼
┌─────────────────────────────────────────────────────┐
│ Layer 5: Observability (R/layer_5_observability/)   │
│  Shiny dashboard: inst/shiny/shiny_app.R            │
│  KPMG System Card: system_card.R (70/30 composite)  │
│  SQLite: audit_log, narrative_approvals              │
│  Tabs: Anomaly Overview | Causal Explorer | RLHF    │
└─────────────────────────────────────────────────────┘
```

---

## 5-Layer Causal DAG

The `inst/dag/reserving_dag.txt` file defines the canonical dagitty DAG:

```
L1 Exogenous Shocks
  gdp_growth  unemployment_rate  tort_reform  medical_cpi
      │               │               │             │
      ▼               ▼               ▼             ▼
L2 Exposure / Mix
  wc_payroll_growth   industry_mix_shift
      │                       │
      ▼                       ▼
L3 Frequency / Severity
  claim_frequency    medical_severity    legal_complexity
        │                   │                   │
        ▼                   ▼                   ▼
L4 Reserve Adequacy
  case_reserve_adequacy    ibnr_adequacy
              │                   │
              ▼                   ▼
L5 Development Factors & Ultimates
  ata_factors    ultimate_loss_ratio    loss_reserve
```

Every do-calculus query targets a path from L1–L3 shocks to L5 outcomes,
with back-door adjustment sets identified from the DAG structure.

---

## SQLite Database Schema

Location: `data/database/causal_reserving.db`

| Table | Layer | Key Columns |
|-------|-------|-------------|
| `triangles` | 1 | lob, grcode, accident_year, development_lag, cumulative_paid, cumulative_incurred, earned_premium |
| `ata_factors` | 1 | lob, grcode, accident_year, development_lag, ata_paid, ata_incurred |
| `anomaly_flags` | 2 | lob, grcode, accident_year, development_lag, flag_type, severity, z_score |
| `causal_context_docs` | 3 | lob, grcode, sha256, xml_content, created_at |
| `narrative_registry` | 4 | ccd_sha256, narrative_text, model, tokens_used, rlhf_rating |
| `audit_log` | 5 | event_type, layer, status, details, created_at |
| `system_card_attestations` | 5 | pillar, score, attested_by, notes |
| `narrative_approvals` | 5 | narrative_id, decision, reviewer, rejection_reason |

All writes are **idempotent**: `INSERT OR REPLACE` / check-before-insert pattern.
Schema migrations in `ingest_schedule_p.R::migrate_schema()` are fully replayable.

---

## Multi-Agent Orchestration

The `agents/` directory implements a Python-based multi-agent pipeline using
the Anthropic SDK. An orchestrator Claude agent dispatches tool calls to
per-layer subagents with strict sequencing enforcement.

```
agents/
  1-data-ingestion/CLAUDE.md    ← Layer 1 agent system prompt
  2-anomaly-detection/CLAUDE.md ← Layer 2 agent system prompt
  3-causal-reasoning/CLAUDE.md  ← Layer 3 agent system prompt
  4-narrative/CLAUDE.md         ← Layer 4 agent system prompt
  5-orchestrator/CLAUDE.md      ← Orchestrator system prompt
  run_pipeline.py               ← Agentic loop + sequencing guard
```

**Sequencing rule**: Layer N cannot start until Layer N-1 reports `status: success`.

### MCP Servers (`.mcp.json`)
- `sqlite` — direct DB read access (via `mcp-server-sqlite`)
- `filesystem` — read-only file access to R/, inst/, tests/
- `pipeline` — layer execution via `tools/mcp_pipeline.py`

---

## KPMG Trusted AI System Card

`R/layer_5_observability/system_card.R` implements a **70/30 composite** scoring
framework across 5 governance pillars:

| Pillar | Automated Metric (70%) | Human Attestation (30%) |
|--------|------------------------|--------------------------|
| Data Integrity | Triangle completeness, CCD coverage | Actuary attestation |
| Transparency | Audit log entries, SHA-256 CCD hashes | Actuary attestation |
| Explainability | DAG path coverage in CCDs | Actuary attestation |
| Accountability | RLHF rating rate, approval workflow | Actuary attestation |
| Reliability | API success rate from audit_log | Actuary attestation |

Attestation scores recorded via `record_attestation(con, pillar, score, attested_by)`.
Full card via `compute_system_card(con)`.

---

## Regulatory Context

| Requirement | Implementation |
|-------------|----------------|
| Reproducibility | `temperature = 0` for all Claude calls |
| Auditability | SHA-256 CCD hashing; full audit_log |
| Explainability | do-calculus paths in CCD XML |
| Human oversight | RLHF feedback; narrative approval workflow |
| Data integrity | Idempotent DB writes; schema migration |

Alignment: **CAS E-Forum** standards, **Solvency II** reproducibility principles.
