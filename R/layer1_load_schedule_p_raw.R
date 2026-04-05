# ==============================================================================
# R/layer1_load_schedule_p_raw.R
# Load Raw CAS Schedule P Data for One Line of Business
#
# Reads pre-placed CAS Schedule P CSV files from dest_dir (preferred).
# If the file is absent, attempts to download it from the CAS website using
# a fallback chain of candidate URLs.
#
# Accident-year range is detected automatically from the data, so the same
# code works for both the 1988-1997 (Meyers & Shi) and 1998-2007 (extended)
# datasets without any code changes.
#
# Skill reference: inst/skills/schedule_p_data.md
#
# Required packages: readr, dplyr, DBI, RSQLite, glue
# Do NOT call library() here — loaded by app.R.
#
# Usage:
#   source("R/layer1_ingest_schedule_p.R")
#   source("R/layer1_load_schedule_p_raw.R")
#   result <- load_schedule_p_lob("OL", "data/schedule_p", "data/database/causal_reserving.db")
# ==============================================================================


# -- LOB metadata --------------------------------------------------------------

# Fallback download URLs tried in order when a CSV is not pre-placed locally.
# The first URL that delivers a non-empty file wins.
# Add newly discovered CAS paths at the front of this vector.
# Landing page: https://www.casact.org/publications-research/research/
#               research-resources/loss-reserving-data-pulled-naic-schedule-p
CAS_BASE_URLS <- c(
  "https://www.casact.org/sites/default/files/2026-04",
  "https://www.casact.org/sites/default/files/2026-03",
  "https://www.casact.org/sites/default/files/2026-02",
  "https://www.casact.org/sites/default/files/2026-01",
  "https://www.casact.org/sites/default/files/2025-12",
  "https://www.casact.org/sites/default/files/2025-06",
  "https://www.casact.org/sites/default/files/2025-01",
  "https://www.casact.org/sites/default/files/2021-04",
  "https://www.casact.org/research/reserve_data"
)

#' Return metadata for a CAS Schedule P line of business
#'
#' Provides the local filename and LOB-specific column suffix.
#' Accident-year range is NOT hardcoded here — it is read from the data.
#'
#' @param lob_code Character scalar: one of "OL", "WC", "PL", "CA", "PA", "MM".
#' @return Named list: filename, col_suffix, urls.
lob_metadata <- function(lob_code) {
  lobs <- list(
    OL = list(filename = "othliab_pos.csv",  col_suffix = "_h1"),
    WC = list(filename = "wkcomp_pos.csv",   col_suffix = "_D"),
    PL = list(filename = "prodliab_pos.csv", col_suffix = "_r1"),
    CA = list(filename = "comauto_pos.csv",  col_suffix = "_C"),
    PA = list(filename = "ppauto_pos.csv",   col_suffix = "_B"),
    MM = list(filename = "medmal_pos.csv",   col_suffix = "_f1")
  )
  if (!lob_code %in% names(lobs)) {
    stop(glue::glue(
      "Unknown LOB code '{lob_code}'. Supported: {paste(names(lobs), collapse=', ')}"
    ))
  }
  m       <- lobs[[lob_code]]
  m$urls  <- paste0(CAS_BASE_URLS, "/", m$filename)
  m
}


# -- Download (fallback only) --------------------------------------------------

#' Locate or download a raw CAS Schedule P CSV for one LOB
#'
#' If the file already exists in dest_dir, returns its path immediately without
#' any network access. Only attempts to download when the file is absent and
#' force = FALSE is not set. Tries each URL in CAS_BASE_URLS in order.
#'
#' @param lob_code  Character scalar: LOB code (e.g. "OL", "WC").
#' @param dest_dir  Character scalar: local directory for the CSV file.
#' @param force     Logical: re-download even if the file already exists.
#' @return Character scalar: path to the local CSV file.
download_cas_csv <- function(lob_code, dest_dir, force = FALSE) {
  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE)
    message("Created directory: ", dest_dir)
  }

  meta      <- lob_metadata(lob_code)
  dest_file <- file.path(dest_dir, meta$filename)

  if (file.exists(dest_file) && !force) {
    message(glue::glue("Using local file: {dest_file}"))
    return(invisible(dest_file))
  }

  message(glue::glue("File not found locally. Attempting download for {lob_code}..."))
  old_timeout <- getOption("timeout")
  options(timeout = 300)
  on.exit(options(timeout = old_timeout), add = TRUE)

  download_ok <- FALSE
  for (url in meta$urls) {
    message(glue::glue("  Trying: {url}"))
    ok <- tryCatch({
      utils::download.file(url, destfile = dest_file, mode = "wb", quiet = TRUE)
      TRUE
    }, warning = function(w) FALSE,
       error   = function(e) FALSE)

    if (isTRUE(ok) && file.exists(dest_file) && file.size(dest_file) > 1000L) {
      download_ok <- TRUE
      break
    }
    if (file.exists(dest_file)) unlink(dest_file)
  }

  if (!download_ok) {
    stop(glue::glue(
      "'{meta$filename}' not found locally and all download attempts failed.\n\n",
      "Place the file manually at:\n  {dest_file}\n\n",
      "Download from:\n",
      "  https://www.casact.org/publications-research/research/research-resources/",
      "loss-reserving-data-pulled-naic-schedule-p"
    ))
  }

  message(glue::glue("Downloaded: {dest_file} ({round(file.size(dest_file)/1024)} KB)"))
  invisible(dest_file)
}


# -- Parse raw CAS CSV ---------------------------------------------------------

#' Parse a raw CAS Schedule P CSV into internal tidy format
#'
#' Reads the raw NAIC column schema (GRCODE, AccidentYear, DevelopmentLag,
#' CumPaidLoss_{sfx}, IncurLoss_{sfx}, EarnedPremNet_{sfx}) and returns a
#' data.frame in the internal schema. Works with both the 1988-1997 and
#' 1998-2007 datasets — accident years are taken directly from the data.
#'
#' @param file_path Character scalar: path to the raw CAS CSV file.
#' @param lob_code  Character scalar: LOB code used to resolve column suffixes.
#' @return data.frame with columns: lob, grcode, grname, accident_year,
#'   development_lag, cumulative_paid_loss, cumulative_incurred_loss, earned_premium.
parse_cas_csv <- function(file_path, lob_code) {
  stopifnot(file.exists(file_path))

  meta <- lob_metadata(lob_code)
  sfx  <- meta$col_suffix

  raw <- readr::read_csv(file_path,
                         col_types = readr::cols(.default = readr::col_guess()),
                         show_col_types = FALSE)

  col_paid     <- paste0("CumPaidLoss",   sfx)
  col_incurred <- paste0("IncurLoss",     sfx)
  col_premium  <- paste0("EarnedPremNet", sfx)

  required <- c("GRCODE", "GRNAME", "AccidentYear", "DevelopmentLag",
                col_paid, col_incurred, col_premium)
  missing  <- setdiff(required, names(raw))

  if (length(missing) > 0L) {
    stop(glue::glue(
      "Unexpected column names in {file_path}.\n",
      "Missing: {paste(missing, collapse=', ')}\n",
      "Found:   {paste(names(raw), collapse=', ')}\n",
      "Check inst/skills/schedule_p_data.md for the correct col_suffix for LOB '{lob_code}'."
    ))
  }

  data.frame(
    lob                      = lob_code,
    grcode                   = as.integer(raw$GRCODE),
    grname                   = as.character(raw$GRNAME),
    accident_year            = as.integer(raw$AccidentYear),
    development_lag          = as.integer(raw$DevelopmentLag),
    cumulative_paid_loss     = as.numeric(raw[[col_paid]]),
    cumulative_incurred_loss = as.numeric(raw[[col_incurred]]),
    earned_premium           = as.numeric(raw[[col_premium]]),
    stringsAsFactors = FALSE
  )
}


# -- Company selection ---------------------------------------------------------

#' Select one NAIC company from a parsed Schedule P data.frame
#'
#' Filters the data to a single insurer group. If grcode is provided, that
#' company is selected directly. Otherwise, strategy determines the choice.
#'
#' Selection strategies:
#'   "largest_premium"  — company with the highest total net earned premium
#'   "most_complete"    — company with the most triangle rows
#'
#' The returned data.frame has attribute "company" = list(grcode, grname).
#'
#' @param df       data.frame from parse_cas_csv().
#' @param grcode   Optional integer GRCODE to select a specific company.
#' @param strategy Character scalar: "largest_premium" or "most_complete".
#' @return Filtered data.frame for one company.
select_company <- function(df, grcode = NULL, strategy = "largest_premium") {
  complete <- df[df$earned_premium > 0 &
                   !is.na(df$cumulative_paid_loss) &
                   !is.na(df$cumulative_incurred_loss), ]

  row_counts     <- tapply(seq_len(nrow(complete)), complete$grcode, length)
  eligible_codes <- as.integer(names(row_counts[row_counts >= 10L]))

  if (length(eligible_codes) == 0L) {
    stop("No companies with at least 10 complete triangle rows found in data.")
  }

  if (!is.null(grcode)) {
    grcode <- as.integer(grcode)
    if (!grcode %in% eligible_codes) {
      stop(glue::glue(
        "GRCODE {grcode} not found or has fewer than 10 complete rows.\n",
        "Available GRCODEs with ≥10 rows: {paste(head(eligible_codes, 20), collapse=', ')}..."
      ))
    }
    selected_code <- grcode
  } else {
    eligible_df <- complete[complete$grcode %in% eligible_codes, ]

    if (strategy == "largest_premium") {
      totals        <- tapply(eligible_df$earned_premium, eligible_df$grcode, sum, na.rm = TRUE)
      selected_code <- as.integer(names(which.max(totals)))
    } else if (strategy == "most_complete") {
      selected_code <- as.integer(names(which.max(row_counts[as.character(eligible_codes)])))
    } else {
      stop(glue::glue("Unknown strategy '{strategy}'. Use 'largest_premium' or 'most_complete'."))
    }
  }

  result     <- df[df$grcode == selected_code, ]
  grname_val <- result$grname[1L]

  attr(result, "company") <- list(grcode = selected_code, grname = grname_val)
  message(glue::glue("Selected company: {grname_val} (GRCODE={selected_code}, {nrow(result)} rows)"))
  result
}


# -- SQLite persistence --------------------------------------------------------

#' Upsert one company's triangle data into the triangles table
#'
#' @param con  DBI connection to the SQLite database.
#' @param df   data.frame from select_company().
#' @return Invisible integer: number of rows written.
upsert_company_triangles <- function(con, df) {
  cols <- DBI::dbListFields(con, "triangles")
  if (!"grcode" %in% cols) DBI::dbExecute(con, "ALTER TABLE triangles ADD COLUMN grcode INTEGER")
  if (!"grname" %in% cols) DBI::dbExecute(con, "ALTER TABLE triangles ADD COLUMN grname TEXT")

  df_clean <- df
  attr(df_clean, "company") <- NULL

  lob_val    <- df_clean$lob[1L]
  grcode_val <- df_clean$grcode[1L]
  DBI::dbExecute(con,
    glue::glue_sql("DELETE FROM triangles WHERE lob = {lob_val} AND grcode = {grcode_val}",
                   .con = con))

  DBI::dbWriteTable(con, "triangles", df_clean, append = TRUE, overwrite = FALSE)
  invisible(nrow(df_clean))
}


# -- Main entry point ----------------------------------------------------------

#' Load CAS Schedule P data for one line of business end-to-end
#'
#' Full pipeline: locate/download CSV -> parse -> select one company ->
#' upsert triangles -> compute and upsert ATA factors.
#'
#' Pre-place CSV files in dest_dir (e.g. data/schedule_p/wkcomp_pos.csv) to
#' skip downloading entirely. Accident-year range is read from the data.
#'
#' @param lob_code       Character scalar: LOB code ("OL", "WC", ...).
#' @param dest_dir       Character scalar: directory containing CSV files.
#' @param db_path        Character scalar: path to SQLite database.
#' @param grcode         Optional integer GRCODE to pin a specific company.
#' @param strategy       Character scalar: "largest_premium" (default) or "most_complete".
#' @param force_download Logical: re-download even if CSV already exists.
#' @return Invisible named list: grcode, grname, lob, n_triangle_rows, n_ata_rows.
load_schedule_p_lob <- function(lob_code,
                                 dest_dir,
                                 db_path,
                                 grcode         = NULL,
                                 strategy       = "largest_premium",
                                 force_download = FALSE) {
  if (!file.exists(db_path)) {
    if (!exists("initialise_database", mode = "function")) {
      source(file.path(dirname(sys.frame(1)$ofile %||% "R"), "ingest_schedule_p.R"))
    }
    initialise_database(db_path)
  } else {
    con_check <- DBI::dbConnect(RSQLite::SQLite(), db_path)
    tryCatch(migrate_schema(con_check), finally = DBI::dbDisconnect(con_check))
  }

  file_path  <- download_cas_csv(lob_code, dest_dir, force = force_download)

  message(glue::glue("Parsing {lob_code} data..."))
  df_all <- parse_cas_csv(file_path, lob_code)
  message(glue::glue("  Rows: {nrow(df_all)}, companies: {length(unique(df_all$grcode))}, ",
                     "AY range: {min(df_all$accident_year)}\u2013{max(df_all$accident_year)}"))

  df_company <- select_company(df_all, grcode = grcode, strategy = strategy)
  company    <- attr(df_company, "company")

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  n_tri <- upsert_company_triangles(con, df_company)
  message(glue::glue("  Upserted {n_tri} triangle rows into {db_path}"))

  if (!exists("compute_ata_factors", mode = "function")) source("R/ingest_schedule_p.R")
  ata_df <- compute_ata_factors(df_company)

  if (nrow(ata_df) > 0L) {
    cols_ata <- DBI::dbListFields(con, "ata_factors")
    if (!"grcode" %in% cols_ata) DBI::dbExecute(con, "ALTER TABLE ata_factors ADD COLUMN grcode INTEGER")
    ata_df$grcode <- company$grcode
    DBI::dbExecute(con,
      glue::glue_sql("DELETE FROM ata_factors WHERE lob = {lob_code} AND grcode = {company$grcode}",
                     .con = con))
    DBI::dbWriteTable(con, "ata_factors", ata_df, append = TRUE, overwrite = FALSE)
  }

  message(glue::glue(
    "Load complete: {company$grname} (GRCODE={company$grcode}), ",
    "{n_tri} triangle rows, {nrow(ata_df)} ATA rows."
  ))

  invisible(list(
    grcode          = company$grcode,
    grname          = company$grname,
    lob             = lob_code,
    n_triangle_rows = n_tri,
    n_ata_rows      = nrow(ata_df)
  ))
}


# -- Convenience: list eligible companies -------------------------------------

#' List eligible companies in a CAS Schedule P CSV
#'
#' Reads (or downloads) the CSV and returns all companies with ≥10 complete
#' rows, sorted by total earned premium descending.
#'
#' @param lob_code  Character scalar: LOB code.
#' @param dest_dir  Character scalar: directory containing CSV files.
#' @return data.frame: grcode, grname, n_rows, total_premium.
list_schedule_p_companies <- function(lob_code, dest_dir) {
  file_path <- download_cas_csv(lob_code, dest_dir)
  df        <- parse_cas_csv(file_path, lob_code)

  complete <- df[df$earned_premium > 0 &
                   !is.na(df$cumulative_paid_loss) &
                   !is.na(df$cumulative_incurred_loss), ]

  result <- do.call(rbind, lapply(split(complete, complete$grcode), function(g) {
    data.frame(grcode = g$grcode[1L], grname = g$grname[1L],
               n_rows = nrow(g), total_premium = sum(g$earned_premium, na.rm = TRUE),
               stringsAsFactors = FALSE)
  }))

  result <- result[result$n_rows >= 10L, ]
  result[order(-result$total_premium), ]
}
