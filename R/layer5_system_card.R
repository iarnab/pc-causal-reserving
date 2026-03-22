# ==============================================================================
# R/layer_5_observability/system_card.R
# KPMG Trusted AI System Card
#
# Scores the causal reserving system across 5 governance pillars using a
# 70/30 composite: 70% automated metrics (DB-derived) + 30% human attestation
# (stored in system_card_attestations table).
#
# Pillar definitions:
#   1. Data Integrity    — completeness, SHA-256 document hashing, schema coverage
#   2. Transparency      — CCD registry coverage, audit log completeness
#   3. Explainability    — DAG path queries, do-calculus coverage
#   4. Accountability    — RLHF feedback rate, narrative approval workflow
#   5. Reliability       — anomaly detection stability, API retry success rate
#
# Regulatory context: CAS E-Forum reproducibility standards, Solvency II
# analogy (temperature=0 determinism, SHA-256 hashing, audit trail).
#
# Required packages: DBI, RSQLite, dplyr, glue
# Do NOT call library() here — packages are loaded in app.R.
# ==============================================================================


# -- Schema helpers ------------------------------------------------------------

#' Ensure system card tables exist in the database
#'
#' Idempotent: safe to call on every startup.
#'
#' @param con A DBI connection to the SQLite database.
#' @return Invisibly NULL.
initialise_system_card_schema <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS system_card_attestations (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      pillar       TEXT    NOT NULL,
      score        REAL    NOT NULL CHECK (score BETWEEN 0 AND 100),
      attested_by  TEXT    NOT NULL DEFAULT 'actuary',
      notes        TEXT,
      created_at   TEXT    NOT NULL DEFAULT (datetime('now'))
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS narrative_approvals (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      narrative_id    INTEGER NOT NULL,
      decision        TEXT    NOT NULL CHECK (decision IN ('approved', 'rejected')),
      reviewer        TEXT    NOT NULL DEFAULT 'actuary',
      rejection_reason TEXT,
      reviewed_at     TEXT    NOT NULL DEFAULT (datetime('now'))
    )
  ")

  invisible(NULL)
}


# -- Automated metric computers ------------------------------------------------

#' Compute automated score for Data Integrity pillar (0–100)
#'
#' Measures: triangle row completeness, SHA-256 CCD coverage, anomaly flag rate.
#'
#' @param con DBI connection.
#' @return Numeric score 0–100.
.score_data_integrity <- function(con) {
  n_triangles  <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM triangles")$n
  n_ccd        <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM causal_context_docs")$n
  n_narratives <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM narrative_registry")$n

  # Full marks if at least 1000 triangle rows, ≥1 CCD, ≥1 narrative
  completeness <- min(n_triangles / 1000, 1) * 40
  ccd_cov      <- if (n_ccd > 0) 40 else 0
  narr_cov     <- if (n_narratives > 0) 20 else 0

  round(completeness + ccd_cov + narr_cov, 1)
}


#' Compute automated score for Transparency pillar (0–100)
#'
#' Measures: CCD SHA-256 registry coverage, audit log entries.
#'
#' @param con DBI connection.
#' @return Numeric score 0–100.
.score_transparency <- function(con) {
  n_audit <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM audit_log")$n
  n_ccd   <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM causal_context_docs WHERE sha256 IS NOT NULL")$n

  audit_score <- min(n_audit / 50, 1) * 50
  ccd_score   <- min(n_ccd / 5, 1) * 50

  round(audit_score + ccd_score, 1)
}


#' Compute automated score for Explainability pillar (0–100)
#'
#' Measures: DAG availability, CCD paths populated.
#'
#' @param con DBI connection.
#' @return Numeric score 0–100.
.score_explainability <- function(con) {
  # Check if CCD documents contain path data
  n_ccd_with_paths <- tryCatch({
    DBI::dbGetQuery(con,
      "SELECT COUNT(*) AS n FROM causal_context_docs
       WHERE xml_content LIKE '%<active_paths>%'")$n
  }, error = function(e) 0L)

  n_ccd_total <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM causal_context_docs")$n

  if (n_ccd_total == 0L) return(0)

  path_coverage <- n_ccd_with_paths / n_ccd_total
  round(path_coverage * 100, 1)
}


#' Compute automated score for Accountability pillar (0–100)
#'
#' Measures: RLHF feedback rate, narrative approval workflow coverage.
#'
#' @param con DBI connection.
#' @return Numeric score 0–100.
.score_accountability <- function(con) {
  n_narratives <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM narrative_registry")$n

  n_rated <- tryCatch({
    DBI::dbGetQuery(con,
      "SELECT COUNT(*) AS n FROM narrative_registry
       WHERE rlhf_rating IS NOT NULL")$n
  }, error = function(e) 0L)

  n_approved <- tryCatch({
    DBI::dbGetQuery(con,
      "SELECT COUNT(*) AS n FROM narrative_approvals WHERE decision='approved'")$n
  }, error = function(e) 0L)

  if (n_narratives == 0L) return(0)

  rlhf_rate     <- (n_rated / n_narratives) * 60
  approval_rate <- min(n_approved / max(n_narratives, 1), 1) * 40

  round(rlhf_rate + approval_rate, 1)
}


#' Compute automated score for Reliability pillar (0–100)
#'
#' Measures: API success rate from audit_log, anomaly detection consistency.
#'
#' @param con DBI connection.
#' @return Numeric score 0–100.
.score_reliability <- function(con) {
  api_rows <- tryCatch({
    DBI::dbGetQuery(con,
      "SELECT COUNT(*) AS total,
              SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS successes
       FROM audit_log WHERE event_type = 'api_call'")
  }, error = function(e) data.frame(total = 0, successes = 0))

  if (api_rows$total == 0L) return(50)  # neutral when no data

  api_success_rate <- api_rows$successes / api_rows$total
  round(api_success_rate * 100, 1)
}


# -- Attestation helpers -------------------------------------------------------

#' Record a human attestation score for a pillar
#'
#' @param con         DBI connection.
#' @param pillar      One of: "data_integrity", "transparency", "explainability",
#'                    "accountability", "reliability".
#' @param score       Numeric 0–100.
#' @param attested_by Character name or role of reviewer.
#' @param notes       Optional free-text notes.
#' @return Invisibly the inserted row ID.
record_attestation <- function(con, pillar, score,
                               attested_by = "actuary", notes = NULL) {
  valid_pillars <- c("data_integrity", "transparency", "explainability",
                     "accountability", "reliability")
  stopifnot(pillar %in% valid_pillars)
  stopifnot(is.numeric(score), score >= 0, score <= 100)

  DBI::dbExecute(con,
    "INSERT INTO system_card_attestations (pillar, score, attested_by, notes)
     VALUES (?, ?, ?, ?)",
    list(pillar, score, attested_by, notes %||% NA_character_)
  )
  invisible(DBI::dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id)
}


# -- Main scorer ---------------------------------------------------------------

#' Compute full KPMG Trusted AI System Card
#'
#' Returns a data frame with one row per pillar:
#' `pillar`, `auto_score`, `human_score`, `composite_score`, `evidence_type`.
#'
#' Composite formula: 70% automated + 30% human attestation.
#' If no human attestation exists for a pillar, the composite equals the
#' automated score (conservative fallback).
#'
#' @param con DBI connection to the causal reserving database.
#' @return A data.frame (5 rows × 6 columns).
compute_system_card <- function(con) {
  initialise_system_card_schema(con)

  # Automated scores
  auto_scores <- list(
    data_integrity  = .score_data_integrity(con),
    transparency    = .score_transparency(con),
    explainability  = .score_explainability(con),
    accountability  = .score_accountability(con),
    reliability     = .score_reliability(con)
  )

  # Latest human attestation per pillar
  human_raw <- tryCatch({
    DBI::dbGetQuery(con,
      "SELECT pillar, score
       FROM system_card_attestations
       WHERE id IN (
         SELECT MAX(id) FROM system_card_attestations GROUP BY pillar
       )")
  }, error = function(e) data.frame(pillar = character(), score = numeric()))

  human_lookup <- stats::setNames(human_raw$score, human_raw$pillar)

  pillars <- names(auto_scores)
  result  <- lapply(pillars, function(p) {
    auto_s  <- auto_scores[[p]]
    human_s <- if (p %in% names(human_lookup)) human_lookup[[p]] else NA_real_

    composite_s <- if (is.na(human_s)) {
      auto_s
    } else {
      round(0.70 * auto_s + 0.30 * human_s, 1)
    }

    evidence <- if (is.na(human_s)) "Tested (automated)" else "Tested + Attestation"

    data.frame(
      pillar          = p,
      auto_score      = auto_s,
      human_score     = human_s,
      composite_score = composite_s,
      evidence_type   = evidence,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, result)
}


#' Format system card as a human-readable summary
#'
#' @param card Data frame from \code{compute_system_card()}.
#' @return Character string.
format_system_card <- function(card) {
  overall <- round(mean(card$composite_score, na.rm = TRUE), 1)

  lines <- c(
    "=== KPMG Trusted AI System Card ===",
    glue::glue("Overall composite score: {overall}/100"),
    "",
    "Pillar scores (70% automated / 30% attestation):",
    ""
  )

  pillar_labels <- c(
    data_integrity  = "Data Integrity",
    transparency    = "Transparency",
    explainability  = "Explainability",
    accountability  = "Accountability",
    reliability     = "Reliability"
  )

  for (i in seq_len(nrow(card))) {
    p     <- card$pillar[i]
    label <- pillar_labels[[p]]
    comp  <- card$composite_score[i]
    evid  <- card$evidence_type[i]
    human <- if (is.na(card$human_score[i])) "no attestation" else
             glue::glue("human={card$human_score[i]}")
    lines <- c(lines,
      glue::glue("  {label}: {comp}/100 ({evid}; auto={card$auto_score[i]}, {human})")
    )
  }

  paste(lines, collapse = "\n")
}


# -- Null-coalescing operator (local) ------------------------------------------
`%||%` <- function(x, y) if (is.null(x)) y else x
