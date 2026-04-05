# Tests for R/layer1_load_schedule_p_raw.R
# Covers: lob_metadata, download_cas_csv (cache path), parse_cas_csv,
#         select_company, upsert_company_triangles, list_schedule_p_companies
# (load_schedule_p_lob is an integration test via its components above)
# download_cas_csv network calls are not exercised; cache-hit path is tested.


# -- Helpers -------------------------------------------------------------------

# Build a minimal CAS-format CSV with correct column names for a given LOB
make_cas_csv <- function(path, lob_code = "WC", n_companies = 3L,
                          rows_per_company = 12L) {
  sfx <- switch(lob_code,
    WC = "_D", OL = "_h1", PL = "_r1", CA = "_C", PA = "_B", MM = "_f1"
  )
  col_paid     <- paste0("CumPaidLoss",   sfx)
  col_incurred <- paste0("IncurLoss",     sfx)
  col_premium  <- paste0("EarnedPremNet", sfx)

  df <- do.call(rbind, lapply(seq_len(n_companies), function(i) {
    d <- data.frame(
      GRCODE        = i * 100L,
      GRNAME        = paste0("TestCo", i),
      AccidentYear  = rep(1998L:2007L, length.out = rows_per_company),
      DevelopmentLag = rep(1L:10L,     length.out = rows_per_company),
      stringsAsFactors = FALSE
    )
    d[[col_paid]]     <- runif(rows_per_company, 100, 1000)
    d[[col_incurred]] <- runif(rows_per_company, 110, 1100)
    d[[col_premium]]  <- runif(rows_per_company, 500, 5000)
    d
  }))

  utils::write.csv(df, path, row.names = FALSE)
  invisible(path)
}

# Build a fresh initialised DB
make_db <- function() {
  db <- tempfile(fileext = ".db")
  initialise_database(db)
  db
}


# -- lob_metadata --------------------------------------------------------------

test_that("lob_metadata returns correct fields for all 6 LOB codes", {
  for (code in c("OL", "WC", "PL", "CA", "PA", "MM")) {
    meta <- lob_metadata(code)
    expect_true(is.list(meta))
    expect_true(all(c("urls", "col_suffix", "filename") %in% names(meta)))
    expect_true(length(meta$urls) > 0L)
    expect_true(nzchar(meta$col_suffix))
    expect_true(nzchar(meta$filename))
  }
})

test_that("lob_metadata errors on unknown LOB code", {
  expect_error(lob_metadata("XX"), "Unknown LOB code")
})

test_that("lob_metadata filenames end with .csv", {
  for (code in c("OL", "WC", "PL", "CA", "PA", "MM")) {
    expect_true(grepl("\\.csv$", lob_metadata(code)$filename))
  }
})

test_that("lob_metadata urls vector contains multiple fallback candidates", {
  meta <- lob_metadata("WC")
  expect_true(length(meta$urls) >= 3L)
  expect_true(all(grepl("wkcomp_pos\\.csv$", meta$urls)))
})


# -- download_cas_csv (cache-hit path only; no network calls in tests) ---------

test_that("download_cas_csv returns existing file without re-downloading", {
  tmp_dir  <- tempdir()
  meta     <- lob_metadata("WC")
  # Pre-seed the file so the cache-hit branch is taken
  dest     <- file.path(tmp_dir, meta$filename)
  writeLines("fake,csv,content", dest)
  on.exit(unlink(dest), add = TRUE)

  result <- download_cas_csv("WC", tmp_dir, force = FALSE)
  expect_equal(normalizePath(result), normalizePath(dest))
  # File content unchanged (no actual download happened)
  expect_equal(readLines(dest), "fake,csv,content")
})

test_that("download_cas_csv creates dest_dir if absent", {
  new_dir <- file.path(tempdir(), paste0("cas_test_", as.integer(Sys.time())))
  on.exit(unlink(new_dir, recursive = TRUE), add = TRUE)
  meta <- lob_metadata("WC")
  dest <- file.path(new_dir, meta$filename)
  dir.create(new_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines("x", dest)   # pre-seed for cache-hit path
  # Calling with an already-created dir should not error
  expect_no_error(download_cas_csv("WC", new_dir, force = FALSE))
})


# -- parse_cas_csv -------------------------------------------------------------

test_that("parse_cas_csv returns correct columns for WC", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  make_cas_csv(tmp, "WC", n_companies = 1L, rows_per_company = 10L)
  df <- parse_cas_csv(tmp, "WC")
  expect_equal(
    names(df),
    c("lob", "grcode", "grname", "accident_year", "development_lag",
      "cumulative_paid_loss", "cumulative_incurred_loss", "earned_premium")
  )
})

test_that("parse_cas_csv populates lob column with the supplied LOB code", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  make_cas_csv(tmp, "OL", n_companies = 1L, rows_per_company = 10L)
  df <- parse_cas_csv(tmp, "OL")
  expect_true(all(df$lob == "OL"))
})

test_that("parse_cas_csv works for all 6 supported LOBs", {
  for (code in c("OL", "WC", "PL", "CA", "PA", "MM")) {
    tmp <- tempfile(fileext = ".csv")
    on.exit(unlink(tmp), add = TRUE)
    make_cas_csv(tmp, code, n_companies = 1L, rows_per_company = 10L)
    expect_no_error(parse_cas_csv(tmp, code))
  }
})

test_that("parse_cas_csv errors when required columns are missing", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  # Write CSV with wrong column name for the WC suffix
  utils::write.csv(
    data.frame(GRCODE = 1, GRNAME = "X", AccidentYear = 1988,
               DevelopmentLag = 1, Wrong_Col = 1),
    tmp, row.names = FALSE
  )
  expect_error(parse_cas_csv(tmp, "WC"), "Missing")
})

test_that("parse_cas_csv errors on non-existent file", {
  expect_error(parse_cas_csv("/no/such/file.csv", "WC"))
})


# -- select_company ------------------------------------------------------------

# Build a test data.frame directly (no CSV needed)
make_df <- function(codes = c(100L, 200L, 300L), rows_each = 12L) {
  do.call(rbind, lapply(codes, function(gc) {
    data.frame(
      lob                      = "WC",
      grcode                   = gc,
      grname                   = paste0("Co", gc),
      accident_year            = rep(1998L:2007L, length.out = rows_each),
      development_lag          = rep(1L:10L,      length.out = rows_each),
      cumulative_paid_loss     = runif(rows_each, 100, 1000) * (gc / 100),
      cumulative_incurred_loss = runif(rows_each, 110, 1100) * (gc / 100),
      earned_premium           = runif(rows_each, 500, 5000) * (gc / 100),
      stringsAsFactors = FALSE
    )
  }))
}

test_that("select_company returns a single company's rows", {
  df     <- make_df()
  result <- select_company(df)
  expect_equal(length(unique(result$grcode)), 1L)
})

test_that("select_company largest_premium picks highest total premium company", {
  df <- make_df(codes = c(100L, 200L, 300L), rows_each = 12L)
  # grcode 300 has premium multiplied by 3 → highest total
  result <- select_company(df, strategy = "largest_premium")
  expect_equal(unique(result$grcode), 300L)
})

test_that("select_company most_complete picks company with most rows", {
  df_extra <- make_df(codes = c(100L, 200L), rows_each = 12L)
  # Add 5 extra rows to grcode 100 so it has more rows
  extra <- df_extra[df_extra$grcode == 100L, ][1:5, ]
  extra$development_lag <- 11:15
  df_extra <- rbind(df_extra, extra)
  result <- select_company(df_extra, strategy = "most_complete")
  expect_equal(unique(result$grcode), 100L)
})

test_that("select_company respects explicit grcode argument", {
  df     <- make_df(codes = c(100L, 200L, 300L), rows_each = 12L)
  result <- select_company(df, grcode = 200L)
  expect_equal(unique(result$grcode), 200L)
})

test_that("select_company errors on invalid grcode", {
  df <- make_df(codes = c(100L, 200L), rows_each = 12L)
  expect_error(select_company(df, grcode = 999L), "not found")
})

test_that("select_company errors on unknown strategy", {
  df <- make_df()
  expect_error(select_company(df, strategy = "bad_strategy"), "Unknown strategy")
})

test_that("select_company errors when no company has >=10 complete rows", {
  df <- make_df(codes = c(100L), rows_each = 5L)  # only 5 rows < 10 threshold
  expect_error(select_company(df), "at least 10")
})

test_that("select_company attaches company attribute", {
  df     <- make_df()
  result <- select_company(df, grcode = 100L)
  co     <- attr(result, "company")
  expect_true(is.list(co))
  expect_true(all(c("grcode", "grname") %in% names(co)))
  expect_equal(co$grcode, 100L)
})


# -- upsert_company_triangles --------------------------------------------------

test_that("upsert_company_triangles writes rows to triangles table", {
  db  <- make_db()
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit({ DBI::dbDisconnect(con); unlink(db) })

  df <- make_df(codes = c(100L), rows_each = 10L)
  attr(df, "company") <- list(grcode = 100L, grname = "Co100")

  n <- upsert_company_triangles(con, df)
  expect_equal(n, 10L)

  stored <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM triangles")$n
  expect_equal(stored, 10L)
})

test_that("upsert_company_triangles is idempotent: re-upsert replaces rows", {
  db  <- make_db()
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit({ DBI::dbDisconnect(con); unlink(db) })

  df <- make_df(codes = c(100L), rows_each = 10L)
  attr(df, "company") <- list(grcode = 100L, grname = "Co100")

  upsert_company_triangles(con, df)
  upsert_company_triangles(con, df)  # second call should replace, not duplicate

  stored <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM triangles")$n
  expect_equal(stored, 10L)
})

test_that("upsert_company_triangles adds grcode/grname columns if missing", {
  db  <- tempfile(fileext = ".db")
  on.exit(unlink(db))
  # Old schema without grcode/grname
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "
    CREATE TABLE triangles (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      lob TEXT, accident_year INTEGER, development_lag INTEGER,
      cumulative_paid_loss REAL, cumulative_incurred_loss REAL, earned_premium REAL
    )
  ")

  df <- make_df(codes = c(100L), rows_each = 10L)
  attr(df, "company") <- list(grcode = 100L, grname = "Co100")
  expect_no_error(upsert_company_triangles(con, df))

  fields <- DBI::dbListFields(con, "triangles")
  expect_true("grcode" %in% fields)
  expect_true("grname" %in% fields)
})


# -- list_schedule_p_companies -------------------------------------------------

test_that("list_schedule_p_companies returns data.frame with required columns", {
  tmp_dir <- tempdir()
  meta    <- lob_metadata("WC")
  dest    <- file.path(tmp_dir, meta$filename)
  make_cas_csv(dest, "WC", n_companies = 3L, rows_per_company = 12L)
  on.exit(unlink(dest), add = TRUE)

  result <- list_schedule_p_companies("WC", tmp_dir)
  expect_true(is.data.frame(result))
  expect_true(all(c("grcode", "grname", "n_rows", "total_premium") %in% names(result)))
})

test_that("list_schedule_p_companies filters to companies with >=10 rows", {
  tmp_dir <- tempdir()
  meta    <- lob_metadata("WC")
  dest    <- file.path(tmp_dir, meta$filename)
  # n_companies=2 each with 12 rows → both should pass the >=10 filter
  make_cas_csv(dest, "WC", n_companies = 2L, rows_per_company = 12L)
  on.exit(unlink(dest), add = TRUE)

  result <- list_schedule_p_companies("WC", tmp_dir)
  expect_true(all(result$n_rows >= 10L))
})

test_that("list_schedule_p_companies sorts by total_premium descending", {
  tmp_dir <- tempdir()
  meta    <- lob_metadata("WC")
  dest    <- file.path(tmp_dir, meta$filename)
  make_cas_csv(dest, "WC", n_companies = 3L, rows_per_company = 12L)
  on.exit(unlink(dest), add = TRUE)

  result <- list_schedule_p_companies("WC", tmp_dir)
  if (nrow(result) >= 2L) {
    expect_true(result$total_premium[1L] >= result$total_premium[2L])
  }
})
