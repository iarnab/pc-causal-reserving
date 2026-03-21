# ==============================================================================
# R/layer_1_data/ingest_schedule_p.R
# Schedule P Data Ingestion & Triangle Construction
#
# Ingests CAS Schedule P CSV data, constructs development triangles, computes
# age-to-age (ATA) factors, and persists all results to SQLite. Initialises
# the database schema on first run.
#
# Required packages: DBI, RSQLite, dplyr, tidyr, readr, openxlsx
# Do NOT call library() here — loaded by app.R.
#
# Usage:
#   source("R/layer_1_data/ingest_schedule_p.R")
#   db_path <- "data/database/reserving.db"
#   initialise_database(db_path)
#   ingest_schedule_p("data/schedule_p/", db_path, lines = "WC")
# ==============================================================================


# -- Database schema -----------------------------------------------------------

#' Initialise SQLite database schema
#'
#' Creates all required tables if they do not already exist. Idempotent —
#' safe to call multiple times.
#'
#' @param db_path Character scalar: path to the SQLite database file.
#' @return Invisible NULL.
initialise_database <- function(db_path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS triangles (
      id                    INTEGER PRIMARY KEY AUTOINCREMENT,
      lob                   TEXT    NOT NULL,
      accident_year         INTEGER NOT NULL,
      development_lag       INTEGER NOT NULL,
      cumulative_paid_loss  REAL,
      cumulative_incurred_loss REAL,
      earned_premium        REAL,
      ingested_at           TEXT    DEFAULT (datetime('now')),
      UNIQUE(lob, accident_year, development_lag)
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS ata_factors (
      id                INTEGER PRIMARY KEY AUTOINCREMENT,
      lob               TEXT    NOT NULL,
      accident_year     INTEGER NOT NULL,
      from_lag          INTEGER NOT NULL,
      to_lag            INTEGER NOT NULL,
      ata_paid          REAL,
      ata_incurred      REAL,
      computed_at       TEXT    DEFAULT (datetime('now')),
      UNIQUE(lob, accident_year, from_lag, to_lag)
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS anomaly_flags (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      lob              TEXT    NOT NULL,
      accident_year    INTEGER NOT NULL,
      development_lag  INTEGER,
      rule_id          TEXT    NOT NULL,
      severity         TEXT    NOT NULL CHECK(severity IN ('error','warning','info')),
      observed         REAL,
      expected         REAL,
      message          TEXT,
      detected_at      TEXT    DEFAULT (datetime('now'))
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS causal_context_docs (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      sha256       TEXT    NOT NULL UNIQUE,
      lob          TEXT    NOT NULL,
      accident_year INTEGER NOT NULL,
      ccd_xml      TEXT    NOT NULL,
      generated_at TEXT    DEFAULT (datetime('now'))
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS narrative_registry (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      narrative_id   TEXT    NOT NULL UNIQUE,
      lob            TEXT    NOT NULL,
      accident_year  INTEGER NOT NULL,
      ccd_sha256     TEXT    REFERENCES causal_context_docs(sha256),
      narrative_text TEXT,
      reviewer_id    TEXT,
      rating_accuracy    INTEGER CHECK(rating_accuracy    BETWEEN 1 AND 5),
      rating_coherence   INTEGER CHECK(rating_coherence   BETWEEN 1 AND 5),
      rating_tone        INTEGER CHECK(rating_tone        BETWEEN 1 AND 5),
      rating_completeness INTEGER CHECK(rating_completeness BETWEEN 1 AND 5),
      rating_conciseness INTEGER CHECK(rating_conciseness BETWEEN 1 AND 5),
      reviewer_notes TEXT,
      created_at     TEXT    DEFAULT (datetime('now'))
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS audit_log (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      event_type   TEXT    NOT NULL,
      lob          TEXT,
      accident_year INTEGER,
      prompt_sha256 TEXT,
      model        TEXT,
      tokens_used  INTEGER,
      duration_ms  INTEGER,
      logged_at    TEXT    DEFAULT (datetime('now'))
    )
  ")

  invisible(NULL)
}


# -- CSV ingestion -------------------------------------------------------------

#' Parse a Schedule P triangle CSV file
#'
#' Reads a raw loss triangle CSV and returns a tidy long-format data.frame.
#' The CSV must have columns: lob, accident_year, development_lag,
#' cumulative_paid_loss, cumulative_incurred_loss, earned_premium.
#'
#' @param file_path Character scalar: path to the CSV file.
#' @param lob       Optional character scalar to override the lob column.
#' @return A data.frame with the six standard columns plus a validated lob.
parse_triangle_csv <- function(file_path, lob = NULL) {
  stopifnot(file.exists(file_path))

  df <- readr::read_csv(file_path, col_types = readr::cols(
    lob                      = readr::col_character(),
    accident_year            = readr::col_integer(),
    development_lag          = readr::col_integer(),
    cumulative_paid_loss     = readr::col_double(),
    cumulative_incurred_loss = readr::col_double(),
    earned_premium           = readr::col_double()
  ), show_col_types = FALSE)

  required_cols <- c("accident_year", "development_lag",
                     "cumulative_paid_loss", "cumulative_incurred_loss",
                     "earned_premium")
  missing <- setdiff(required_cols, names(df))
  if (length(missing) > 0L) {
    stop(glue::glue("Missing columns in {file_path}: {paste(missing, collapse=', ')}"))
  }

  if (!is.null(lob)) df$lob <- lob
  if (!"lob" %in% names(df)) {
    stop("CSV has no 'lob' column and no lob argument was provided.")
  }

  df[, c("lob", "accident_year", "development_lag",
         "cumulative_paid_loss", "cumulative_incurred_loss", "earned_premium")]
}


#' Build and persist development triangles from CSV data
#'
#' Reads all CSVs in data_dir for the specified lines of business, parses
#' them with parse_triangle_csv(), and upserts into the triangles table.
#'
#' @param data_dir  Character: path to directory containing Schedule P CSVs.
#' @param db_path   Character: path to the SQLite database.
#' @param lines     Character vector of LOB codes to process. Default: all.
#' @return Invisible integer: total rows inserted/updated.
build_development_triangles <- function(data_dir, db_path,
                                        lines = c("WC","CMP","OL","CA","MM")) {
  stopifnot(dir.exists(data_dir))

  csv_files <- list.files(data_dir, pattern = "\\.csv$", full.names = TRUE)
  if (length(csv_files) == 0L) {
    message("No CSV files found in ", data_dir)
    return(invisible(0L))
  }

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  total_rows <- 0L
  for (f in csv_files) {
    df <- tryCatch(parse_triangle_csv(f), error = function(e) {
      warning(glue::glue("Skipping {f}: {conditionMessage(e)}"))
      NULL
    })
    if (is.null(df)) next

    df_filtered <- df[df$lob %in% lines, ]
    if (nrow(df_filtered) == 0L) next

    DBI::dbWriteTable(con, "triangles", df_filtered,
                      append = TRUE, overwrite = FALSE)
    total_rows <- total_rows + nrow(df_filtered)
  }

  message(glue::glue("Ingested {total_rows} triangle rows into {db_path}"))
  invisible(total_rows)
}


# -- ATA factor computation ----------------------------------------------------

#' Compute age-to-age factors from a long-format triangle data.frame
#'
#' For each LOB × accident year × development period pair, computes the
#' paid and incurred ATA factors: ATA(t) = loss(t+1) / loss(t).
#'
#' @param triangle_df A data.frame with columns: lob, accident_year,
#'   development_lag, cumulative_paid_loss, cumulative_incurred_loss.
#' @return A data.frame with columns: lob, accident_year, from_lag, to_lag,
#'   ata_paid, ata_incurred.
compute_ata_factors <- function(triangle_df) {
  stopifnot(is.data.frame(triangle_df))

  df_sorted <- triangle_df[order(triangle_df$lob,
                                  triangle_df$accident_year,
                                  triangle_df$development_lag), ]

  result <- do.call(rbind, lapply(
    split(df_sorted, list(df_sorted$lob, df_sorted$accident_year)),
    function(grp) {
      if (nrow(grp) < 2L) return(NULL)
      n <- nrow(grp)
      data.frame(
        lob           = grp$lob[seq_len(n - 1L)],
        accident_year = grp$accident_year[seq_len(n - 1L)],
        from_lag      = grp$development_lag[seq_len(n - 1L)],
        to_lag        = grp$development_lag[2L:n],
        ata_paid      = grp$cumulative_paid_loss[2L:n] /
                        grp$cumulative_paid_loss[seq_len(n - 1L)],
        ata_incurred  = grp$cumulative_incurred_loss[2L:n] /
                        grp$cumulative_incurred_loss[seq_len(n - 1L)],
        stringsAsFactors = FALSE
      )
    }
  ))

  result[is.finite(result$ata_paid) & is.finite(result$ata_incurred), ]
}


# -- Main orchestrator ---------------------------------------------------------

#' Ingest Schedule P data end-to-end
#'
#' Full pipeline: parse CSVs -> build triangles -> compute ATA factors ->
#' persist to SQLite. Calls initialise_database() if the DB does not exist.
#'
#' @param data_dir     Character: path to Schedule P CSV directory.
#' @param db_path      Character: path to SQLite database.
#' @param lines        Character vector of LOB codes. Default: WC only.
#' @param force_years  Optional integer vector to restrict accident years.
#' @return Invisible list: list(n_triangle_rows, n_ata_rows).
ingest_schedule_p <- function(data_dir, db_path,
                               lines = "WC", force_years = NULL) {
  if (!file.exists(db_path)) initialise_database(db_path)

  n_tri <- build_development_triangles(data_dir, db_path, lines = lines)

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  triangle_df <- DBI::dbGetQuery(con, glue::glue(
    "SELECT * FROM triangles WHERE lob IN ({paste(shQuote(lines), collapse=',')})"
  ))

  if (!is.null(force_years)) {
    triangle_df <- triangle_df[triangle_df$accident_year %in% force_years, ]
  }

  ata_df <- compute_ata_factors(triangle_df)

  if (nrow(ata_df) > 0L) {
    DBI::dbWriteTable(con, "ata_factors", ata_df,
                      append = TRUE, overwrite = FALSE)
  }

  message(glue::glue(
    "Ingestion complete: {n_tri} triangle rows, {nrow(ata_df)} ATA factor rows."
  ))
  invisible(list(n_triangle_rows = n_tri, n_ata_rows = nrow(ata_df)))
}
