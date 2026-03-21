test_that("initialise_database creates all required tables", {
  db <- tempfile(fileext = ".db")
  on.exit(unlink(db))
  initialise_database(db)

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  tables <- DBI::dbListTables(con)
  expect_true(all(c("triangles", "ata_factors", "anomaly_flags",
                    "causal_context_docs", "narrative_registry",
                    "audit_log") %in% tables))
})

test_that("initialise_database is idempotent", {
  db <- tempfile(fileext = ".db")
  on.exit(unlink(db))
  expect_no_error(initialise_database(db))
  expect_no_error(initialise_database(db))   # second call should not error
})

test_that("parse_triangle_csv returns expected columns", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines(
    "lob,accident_year,development_lag,cumulative_paid_loss,cumulative_incurred_loss,earned_premium\nWC,1988,1,100,120,200\nWC,1988,2,150,160,200",
    tmp
  )
  df <- parse_triangle_csv(tmp)
  expect_equal(names(df), c("lob","accident_year","development_lag",
                              "cumulative_paid_loss","cumulative_incurred_loss",
                              "earned_premium"))
  expect_equal(nrow(df), 2L)
  expect_equal(df$lob, c("WC","WC"))
})

test_that("parse_triangle_csv errors on missing required columns", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines("accident_year,development_lag\n1988,1", tmp)
  expect_error(parse_triangle_csv(tmp), "Missing columns")
})

test_that("compute_ata_factors returns correct values for known triangle", {
  # Simple 3-period triangle: ATA(1->2) = 150/100 = 1.5, ATA(2->3) = 225/150 = 1.5
  df <- data.frame(
    lob                      = "WC",
    accident_year            = 1988L,
    development_lag          = 1:3,
    cumulative_paid_loss     = c(100, 150, 225),
    cumulative_incurred_loss = c(110, 165, 247.5),
    earned_premium           = 500,
    stringsAsFactors = FALSE
  )
  ata <- compute_ata_factors(df)
  expect_equal(nrow(ata), 2L)
  expect_equal(ata$ata_paid,     c(1.5, 1.5), tolerance = 1e-6)
  expect_equal(ata$from_lag,     c(1L, 2L))
  expect_equal(ata$to_lag,       c(2L, 3L))
})

test_that("compute_ata_factors returns zero rows for single-period triangle", {
  df <- data.frame(lob = "WC", accident_year = 1988L, development_lag = 1L,
                   cumulative_paid_loss = 100, cumulative_incurred_loss = 110,
                   earned_premium = 500, stringsAsFactors = FALSE)
  ata <- compute_ata_factors(df)
  expect_equal(nrow(ata), 0L)
})
