# pc-causal-reserving

**Causal Intelligence for P&C Loss Reserving**
*CAS 2026 RFP — Adapting LLMs for Specialized P&C Actuarial Reasoning*

[![R CMD Check](https://github.com/iarnab/pc-causal-reserving/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/iarnab/pc-causal-reserving/actions)
[![License: MPL 2.0](https://img.shields.io/badge/License-MPL_2.0-brightgreen.svg)](LICENSE)

---

## Overview

This repository implements a five-module R pipeline that grounds LLM reserve narratives in explicit causal structure. Instead of passing raw loss triangles to an LLM, we:

1. Detect anomalies in Schedule P development data (ATA Z-scores, diagonal effects)
2. Trace those anomalies through a structured 5-layer causal DAG
3. Construct a **Causal Context Document (CCD)** — a SHA-256-registered XML document encoding the active causal subgraph and do-calculus queries
4. Inject the CCD into a Claude API prompt to produce auditable, counterfactual-capable reserve narratives
5. Collect FCAS-credentialed actuary feedback via an RLHF Shiny dashboard

---

## Architecture

```
Schedule P (CSV)
      |
      v
Layer 1: Data Ingestion (R / SQLite)
  parse_triangle_csv() --> build_development_triangles() --> compute_ata_factors()
      |
      v
Layer 2: Anomaly Detection (anomalize)
  detect_ata_zscore() --> detect_diagonal_effect() --> combine_anomaly_signals()
      |
      v
Layer 3: Causal DAG (dagitty / bnlearn)
  build_reserving_dag() --> query_do_calculus() --> get_dag_paths()
      |
      v
Layer 4: CCD Generator (xml2 / digest)
  generate_ccd() --> build_ccd_xml() --> compute_sha256() --> register_ccd()
      |
      v
Layer 5: LLM Synthesis (Claude API / httr2)
  synthesize_reserve_narrative() --> collect_rlhf_feedback()
      |
      v
Shiny Dashboard (3 tabs: Anomaly Overview | Causal Explorer | RLHF Review)
```

---

## 5-Layer Causal DAG

```
L1 Exogenous Shocks
  gdp_growth  unemployment_rate  tort_reform  medical_cpi
      |               |               |             |
      v               v               v             v
L2 Exposure & Mix Shifts
  payroll_growth         demographic_shift
      |                         |
      v                         v
L3 Claim Frequency & Severity
  claim_frequency  reported_claims  avg_case_value  alae_ratio
                          |               |
                          v               v
L4 Case Reserve Adequacy
          case_reserve_opening  ibnr_emergence
                    |                 |
                    v                 v
L5 Development Factors & Ultimates
        development_factor  tail_factor --> ultimate_loss --> loss_ratio
```

Full dagitty specification: [`inst/dag/reserving_dag.txt`](inst/dag/reserving_dag.txt)

---

## Quickstart

```r
# 1. Install dependencies
Rscript install_packages.R

# 2. Set API key
# Add to .Renviron: ANTHROPIC_API_KEY=sk-ant-...

# 3. Run Shiny dashboard
shiny::runApp("app.R")
```

---

## Module Table

| Layer | File | Key Functions |
|-------|------|---------------|
| 1: Data Ingestion | `R/layer_1_data/ingest_schedule_p.R` | `ingest_schedule_p()`, `compute_ata_factors()`, `initialise_database()` |
| 2: Anomaly Detection | `R/layer_2_anomaly/detect_triangle_anomalies.R` | `detect_ata_zscore()`, `detect_diagonal_effect()` |
| 3: Causal DAG | `R/layer_3_causal/build_reserving_dag.R` | `build_reserving_dag()`, `query_do_calculus()`, `get_dag_paths()` |
| 4: CCD Generator | `R/layer_4_ccd/generate_ccd.R` | `generate_ccd()`, `build_ccd_xml()`, `compute_sha256()` |
| 5: LLM Synthesis | `R/layer_5_llm/synthesize_reserve_narrative.R` | `synthesize_reserve_narrative()`, `collect_rlhf_feedback()` |

---

## Budget & Timeline

| Phase | Funding | Hours | Period |
|-------|---------|-------|--------|
| Phase 1 (CAS grant) | EUR 37,000 (~$40K) | 185 NL hrs | Apr–Aug 2026 |
| Phase 2 (firm match) | EUR 37,000 (~$40K) | 125 hrs US+NL | Apr–Aug 2026 |

Sprint plan: April (data + DAG) → May (anomaly + baseline) → June (CCD + eval round 1) → July (RLHF) → August (paper + submission)

---

## Citation

```
Gupta, A. et al. (2026). Causal Intelligence for P&C Loss Reserving:
Grounding LLM Reserve Narratives in Explicit Causal Structure.
CAS 2026 LLM Research Grant. github.com/iarnab/pc-causal-reserving
```

---

## License

[Mozilla Public License 2.0](LICENSE) — open-source per CAS RFP requirement.
