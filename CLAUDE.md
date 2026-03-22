# CLAUDE.md — pc-causal-reserving

> **AXIOM-P&C**: Causal Intelligence for P&C Loss Reserving
> CAS 2026 RFP — Adapting LLMs for Specialized P&C Actuarial Reasoning
> R package: `actuarialcausalintelligence` v0.1.0 | License: MPL-2.0

---

## Project Purpose

This is a **research codebase**, not a production Shiny app. It implements a
5-layer R pipeline that grounds LLM reserve narratives in explicit causal
structure (do-calculus + Causal Context Documents). The primary deliverable is
a CAS research paper + reproducible software release.

Data source: CAS Schedule P (Workers Compensation, 1988–1997, 10 companies).

---

## 5-Layer Architecture

R packages require all source files to be **directly** inside `R/` (no subdirectories).
Layer organisation is enforced through **file naming prefixes** (`layerN_`).

| Layer | File prefix | Responsibility |
|-------|-------------|----------------|
| **1 — Data** | `R/layer1_*.R` | Ingest Schedule P CSV/Excel → SQLite; build triangles; compute ATA factors |
| **2 — Anomaly** | `R/layer2_*.R` | Z-score flagging; diagonal regression; combine signals |
| **3 — Causal** | `R/layer3_*.R` | DAG construction; do-calculus queries; CCD XML generation |
| **4 — AI** | `R/layer4_*.R` | Claude API wrapper; prompt builders; RLHF feedback |
| **5 — Observability** | `R/layer5_*.R` | Shiny dashboard (5 tabs); KPMG System Card; audit trail |

> **Note**: Using subdirectories inside `R/` is not supported by R CMD build/check —
> `devtools::load_all()` and R CMD check only read `.R` files at the top level of `R/`.

### Layer Constraints (STRICT)

- **Layers 1–3** must NEVER call external APIs (no `httr2::req_perform()` etc.)
- **Layer 4** is the ONLY layer allowed to call the Anthropic API
- Cross-layer communication is exclusively via the **SQLite database** (`data/database/causal_reserving.db`)
- Never import functions from a higher layer into a lower layer
- Shared helpers within a layer go in a `layerN_utils.R` file

---

## Coding Standards

### R Style
- **Naming**: `snake_case` for all objects, functions, and files
- **Pipe**: Always use `|>` (base pipe, R ≥ 4.1). Never use `%>%`
- **Dependencies**: Never use `library()` in sourced scripts. Use `box::use()` or declare at entry point (`app.R`)
- **Paths**: Always use `here::here()` or relative paths. Never hardcode absolute paths
- **Functions**: Keep short, single-purpose. Extract helpers to `R/layerN_utils.R`
- **DAGs**: Every `dagitty` DAG must have a comment block explaining the causal story and economic rationale

### Claude API
- Always use `temperature = 0` for deterministic, reproducible outputs (regulatory requirement)
- System prompt must include CCD content when available
- API key from `.Renviron` only (`ANTHROPIC_API_KEY`). Never hardcode
- All API calls belong in `R/layer4_*.R` files only

### Database
- All writes must be idempotent (check before insert; `INSERT OR REPLACE`)
- Schema migrations in `ingest_schedule_p.R::migrate_schema()` — must be replayable
- Tables: `triangles`, `ata_factors`, `anomaly_flags`, `causal_context_docs`, `narrative_registry`, `audit_log`, `narrative_approvals`, `system_card_attestations`

---

## Git Conventions

Use **Conventional Commits**:

```
feat:     new capability
fix:      bug fix
refactor: code restructure (no behaviour change)
test:     test changes only
docs:     documentation only
chore:    build, CI, tooling
```

**Rules:**
- Never auto-commit — always stage specific files and confirm first
- Never force-push to `main`
- Never commit secrets, `.db` files, or large CSVs
- Feature branches: `claude/<short-description>-<session-id>`

---

## Environment

```
# .Renviron (gitignored)
ANTHROPIC_API_KEY=sk-ant-...
```

Load at session start with `readRenviron(".Renviron")` or via `app.R`.

---

## Testing

Framework: `testthat` (Edition 3)

```r
library(testthat)
test_check("actuarialcausalintelligence")
```

Per-layer test files in `tests/testthat/`:
- `test_layer1_ingestion.R` — schema init, migration, multi-company
- `test_layer2_anomaly.R` — Z-score, diagonal, edge cases
- `test_layer3_causal.R` — DAG construction, do-calculus paths
- `test_layer3_ccd.R` — CCD XML building, SHA-256
- `test_layer4_narrative.R` — prompt building, dry-run (no real API calls)
- `test_layer5_system_card.R` — KPMG pillar scoring

**Key rules:**
- API tests use `dry_run = TRUE` — never make real Claude calls in tests
- Use `withr::local_db_connection()` or temp SQLite path for DB tests
- 100% of new functions need at least one test

---

## Multi-Agent Orchestration (Phase 2)

The `agents/` directory contains a Python-based multi-agent pipeline:

```
agents/
  1-data-ingestion/CLAUDE.md   ← agent system prompt
  2-anomaly-detection/CLAUDE.md
  3-causal-reasoning/CLAUDE.md
  4-narrative/CLAUDE.md
  5-orchestrator/CLAUDE.md
  run_pipeline.py              ← sequential execution guard + tool dispatch
```

**Sequencing rule**: The orchestrator enforces strict layer ordering.
Layer N cannot run until layer N-1 has completed successfully.

MCP servers registered in `.mcp.json`:
- `sqlite` — direct DB queries
- `filesystem` — read-only file access
- `pipeline` — layer execution via `run_pipeline.py`

---

## Key Files

| File | Purpose |
|------|---------|
| `app.R` | Shiny entrypoint — sources all layers |
| `inst/shiny/shiny_app.R` | Full dashboard (5 tabs) |
| `inst/dag/reserving_dag.txt` | Canonical dagitty DAG spec |
| `data-raw/README.md` | Data ingestion instructions |
| `R/layer5_system_card.R` | KPMG Trusted AI System Card |
| `tests/testthat/` | All tests |
| `.github/workflows/R-CMD-check.yaml` | CI/CD |
| `.claude/commands/` | 19 slash command skills (all layers) |
| `agents/run_pipeline.py` | Multi-agent sequential execution guard |
| `docs/architecture.md` | Full system architecture reference |

---

## Prohibited Actions

- Do NOT run `renv::init()` unless explicitly asked
- Do NOT call APIs in layers 1–3
- Do NOT create files outside the established layer structure without approval
- Do NOT commit directly to `main` if a feature branch exists
- Do NOT use `%>%` (use `|>`)
- Do NOT use `library()` in sourced scripts
- Do NOT hardcode file paths

---

## Governance

The KPMG Trusted AI System Card (`R/layer5_system_card.R`) scores
the system across 5 pillars using a **70/30 composite**:
- 70% automated metrics (derived from DB)
- 30% human attestation (stored in `system_card_attestations` table)

**Pillars**: Data Integrity, Transparency, Explainability, Accountability, Reliability

Regulatory alignment: CAS E-Forum standards, Solvency II analogy (reproducibility
requirement drives `temperature=0`).
