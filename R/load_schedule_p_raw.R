# ==============================================================================
# R/layer_1_data/load_schedule_p_raw.R
# Load Raw CAS Schedule P Data for One Line of Business
#
# Downloads the raw CAS Schedule P CSV (wkcomp_pos.csv or othliab_pos.csv),
# parses the NAIC column schema, selects one company, and loads into SQLite.
#
# Skill reference: inst/skills/schedule_p_data.md
#
# Required packages: readr, dplyr, DBI, RSQLite, glue
# Do NOT call library() here — loaded by app.R.
#
# Primary LOB: "OL" (GL Occurrence / Other Liability – Occurrence)
#
# Usage:
#   source("R/layer_1_data/ingest_schedule_p.R")    # for initialise_database()
#   source("R/layer_1_data/load_schedule_p_raw.R")
#   result <- load_schedule_p_lob("OL", "data/schedule_p", "data/database/reserving.db")
# ==============================================================================


# -- LOB metadata --------------------------------------------------------------

#' Return metadata for a CAS Schedule P line of business
#'
#' Provides the download URL, column suffix, and local filename for each
#' supported LOB code. Refer to inst/skills/schedule_p_data.md for details.
#'
#' @param lob_code Character scalar: one of "OL", "WC", "PL", "CA", "PA", "MM".
#' @return Named list: url, col_suffix, filename.
lob_metadata <- function(lob_code) {
  base <- "https://www.casact.org/sites/default/files/2021-04"
  meta <- list(
    OL = list(url = paste0(base, "/othliab_pos.csv"),  col_suffix = "_h1", filename = "othliab_pos.csv"),
    WC = list(url = paste0(base, "/wkcomp_pos.csv"),   col_suffix = "_D",  filename = "wkcomp_pos.csv"),
    PL = list(url = paste0(base, "/prodliab_pos.csv"), col_suffix = "_r1", filename = "prodliab_pos.csv"),
    CA = list(url = paste0(base, "/comauto_pos.csv"),  col_suffix = "_C",  filename = "comauto_pos.csv"),
    PA = list(url = paste0(base, "/ppauto_pos.csv"),   col_suffix = "_B",  filename = "ppauto_pos.csv"),
    MM = list(url = paste0(base, "/medmal_pos.csv"),   col_suffix = "_f1", filename = "medmal_pos.csv")
  )
  if (!lob_code %in% names(meta)) {
    stop(glue::glue(
      "Unknown LOB code '{lob_code}'. Supported: {paste(names(meta), collapse=', ')}"
    ))
  }
  meta[[lob_code]]
}


# -- Download ------------------------------------------------------------------

#' Download a raw CAS Schedule P CSV for one LOB
#'
#' Fetches the file from the CAS website into dest_dir. If the file already
#' exists and force = FALSE, returns the existing path without downloading.
#'
#' @param lob_code  Character scalar: LOB code (e.g. "OL", "WC").
#' @param dest_dir  Character scalar: local directory for the downloaded file.
#' @param force     Logical: re-download even if the file already exists.
#' @return Character scalar: path to the downloaded file.
download_cas_csv <- function(lob_code, dest_dir, force = FALSE) {
  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE)
    message("Created directory: ", dest_dir)
  }

  meta      <- lob_metadata(lob_code)
  dest_file <- file.path(dest_dir, meta$filename)

  if (file.exists(dest_file) && !force) {
    message(glue::glue("Using cached file: {dest_file}"))
    return(invisible(dest_file))
  }

  message(glue::glue("Downloading {lob_code} data from CAS website..."))
  old_timeout <- getOption("timeout")
  options(timeout = 300)
  on.exit(options(timeout = old_timeout), add = TRUE)

  tryCatch(
    utils::download.file(meta$url, destfile = dest_file, mode = "wb", quiet = FALSE),
    error = function(e) {
      stop(glue::glue(
        "Failed to download {meta$url}\n",
        "Error: {conditionMessage(e)}\n",
        "Check your internet connection or download manually and place at: {dest_file}"
      ))
    }
  )

  message(glue::glue("Downloaded: {dest_file} ({round(file.size(dest_file)/1024)} KB)"))
  invisible(dest_file)
}


# -- Parse raw CAS CSV ---------------------------------------------------------

#' Parse a raw CAS Schedule P CSV into internal tidy format
#'
#' Reads the raw NAIC column schema (GRCODE, AccidentYear, DevelopmentLag,
#' CumPaidLoss_{sfx}, IncurLoss_{sfx}, EarnedPremNet_{sfx}) and returns a
#' data.frame in the internal schema used by the triangles SQLite table.
#'
#' The grcode column is included so the caller can filter to one company.
#' See inst/skills/schedule_p_data.md for the full column mapping.
#'
#' @param file_path Character scalar: path to the raw CAS CSV file.
#' @param lob_code  Character scalar: LOB code used to resolve column suffixes.
#' @return data.frame with columns: lob, grcode, grname, accident_year,
#'   development_lag, cumulative_paid_loss, cumulative_incurred_loss, earned_premium.
parse_cas_csv <- function(file_path, lob_code) {
  stopifnot(file.exists(file_path))

  meta <- lob_metadata(lob_code)
  sfx  <- meta$col_suffix

  # Read with flexible column types; column names depend on the LOB suffix
  raw <- readr::read_csv(file_path, col_types = readr::cols(.default = readr::col_guess()),
                         show_col_types = FALSE)

  # Resolve suffixed column names
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
  # Filter to companies with complete upper triangle (non-zero premium, ≥10 rows)
  complete <- df[df$earned_premium > 0 &
                   !is.na(df$cumulative_paid_loss) &
                   !is.na(df$cumulative_incurred_loss), ]

  row_counts    <- tapply(seq_len(nrow(complete)), complete$grcode, length)
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
      totals       <- tapply(eligible_df$earned_premium, eligible_df$grcode, sum, na.rm = TRUE)
      selected_code <- as.integer(names(which.max(totals)))
    } else if (strategy == "most_complete") {
      selected_code <- as.integer(names(which.max(row_counts[eligible_codes])))
    } else {
      stop(glue::glue("Unknown strategy '{strategy}'. Use 'largest_premium' or 'most_complete'."))
    }
  }

  result        <- df[df$grcode == selected_code, ]
  grname_val    <- result$grname[1L]

  attr(result, "company") <- list(grcode = selected_code, grname = grname_val)
  message(glue::glue("Selected company: {grname_val} (GRCODE={selected_code}, {nrow(result)} rows)"))
  result
}


# -- SQLite persistence --------------------------------------------------------

#' Upsert one company's triangle data into the triangles table
#'
#' Adds grcode and grname to the triangles table if not already present
#' (via ALTER TABLE, safe to call multiple times). Then upserts all rows.
#'
#' @param con  DBI connection to the SQLite database.
#' @param df   data.frame from select_company() (includes grcode, grname columns).
#' @return Invisible integer: number of rows written.
upsert_company_triangles <- function(con, df) {
  # Ensure grcode/grname columns exist in the triangles table
  cols <- DBI::dbListFields(con, "triangles")
  if (!"grcode" %in% cols) {
    DBI::dbExecute(con, "ALTER TABLE triangles ADD COLUMN grcode INTEGER")
  }
  if (!"grname" %in% cols) {
    DBI::dbExecute(con, "ALTER TABLE triangles ADD COLUMN grname TEXT")
  }

  # Remove the 'company' attribute before writing
  df_clean        <- df
  attr(df_clean, "company") <- NULL

  # Delete existing rows for this lob/grcode to allow clean upsert
  lob_val   <- df_clean$lob[1L]
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
#' Full pipeline: download raw CSV -> parse -> select one company ->
#' upsert triangles -> compute and upsert ATA factors.
#'
#' Calls initialise_database() from ingest_schedule_p.R if the DB is absent.
#' Calls compute_ata_factors() from ingest_schedule_p.R for ATA computation.
#'
#' @param lob_code       Character scalar: LOB code ("OL", "WC", ...).
#' @param dest_dir       Character scalar: directory for raw CSV cache.
#' @param db_path        Character scalar: path to SQLite database.
#' @param grcode         Optional integer GRCODE to pin a specific company.
#' @param strategy       Character scalar: company selection strategy.
#'                       "largest_premium" (default) or "most_complete".
#' @param force_download Logical: re-download even if CSV already cached.
#' @return Invisible named list: grcode, grname, lob, n_triangle_rows, n_ata_rows.
load_schedule_p_lob <- function(lob_code,
                                 dest_dir,
                                 db_path,
                                 grcode         = NULL,
                                 strategy       = "largest_premium",
                                 force_download = FALSE) {
  # Ensure database exists and schema is initialised
  if (!file.exists(db_path)) {
    if (!exists("initialise_database", mode = "function")) {
      source(file.path(dirname(sys.frame(1)$ofile %||% "R"),
                       "ingest_schedule_p.R"))
    }
    initialise_database(db_path)
  }

  # 1. Download raw CSV
  file_path <- download_cas_csv(lob_code, dest_dir, force = force_download)

  # 2. Parse raw CAS columns → internal schema
  message(glue::glue("Parsing {lob_code} data..."))
  df_all <- parse_cas_csv(file_path, lob_code)
  message(glue::glue("  Raw rows: {nrow(df_all)}, companies: {length(unique(df_all$grcode))}"))

  # 3. Select one company
  df_company <- select_company(df_all, grcode = grcode, strategy = strategy)
  company    <- attr(df_company, "company")

  # 4. Upsert triangles into SQLite
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  n_tri <- upsert_company_triangles(con, df_company)
  message(glue::glue("  Upserted {n_tri} triangle rows into {db_path}"))

  # 5. Compute ATA factors (reuse function from ingest_schedule_p.R)
  if (!exists("compute_ata_factors", mode = "function")) {
    source("R/ingest_schedule_p.R")
  }
  ata_df <- compute_ata_factors(df_company)

  if (nrow(ata_df) > 0L) {
    # Remove existing ATA rows for this lob/company before inserting
    cols_ata <- DBI::dbListFields(con, "ata_factors")
    if (!"grcode" %in% cols_ata) {
      DBI::dbExecute(con, "ALTER TABLE ata_factors ADD COLUMN grcode INTEGER")
    }
    ata_df$grcode <- company$grcode
    DBI::dbExecute(con,
      glue::glue_sql(
        "DELETE FROM ata_factors WHERE lob = {company_lob} AND grcode = {company$grcode}",
        company_lob = lob_code, .con = con
      ))
    DBI::dbWriteTable(con, "ata_factors", ata_df, append = TRUE, overwrite = FALSE)
  }

  n_ata <- nrow(ata_df)
  message(glue::glue(
    "Load complete: {company$grname} (GRCODE={company$grcode}), ",
    "{n_tri} triangle rows, {n_ata} ATA factor rows."
  ))

  invisible(list(
    grcode          = company$grcode,
    grname          = company$grname,
    lob             = lob_code,
    n_triangle_rows = n_tri,
    n_ata_rows      = n_ata
  ))
}


# -- Convenience: list eligible companies -------------------------------------

#' List eligible companies in a raw CAS Schedule P CSV
#'
#' Downloads (if needed) and parses the CSV, then returns a data.frame of
#' all companies with ≥10 complete rows, sorted by total earned premium.
#' Useful for browsing available GRCODEs before calling load_schedule_p_lob().
#'
#' @param lob_code  Character scalar: LOB code.
#' @param dest_dir  Character scalar: directory for raw CSV cache.
#' @return data.frame with columns: grcode, grname, n_rows, total_premium.
list_schedule_p_companies <- function(lob_code, dest_dir) {
  file_path <- download_cas_csv(lob_code, dest_dir)
  df        <- parse_cas_csv(file_path, lob_code)

  complete  <- df[df$earned_premium > 0 &
                    !is.na(df$cumulative_paid_loss) &
                    !is.na(df$cumulative_incurred_loss), ]

  grp <- split(complete, complete$grcode)

  result <- do.call(rbind, lapply(grp, function(g) {
    data.frame(
      grcode        = g$grcode[1L],
      grname        = g$grname[1L],
      n_rows        = nrow(g),
      total_premium = sum(g$earned_premium, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))

  result <- result[result$n_rows >= 10L, ]
  result[order(-result$total_premium), ]
}
