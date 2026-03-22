test_that("initialise_database creates triangles with grcode in UNIQUE constraint", {
  db <- tempfile(fileext = ".db")
  on.exit(unlink(db))
  initialise_database(db)

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  sql <- DBI::dbGetQuery(con,
    "SELECT sql FROM sqlite_master WHERE type='table' AND name='triangles'"
  )$sql[[1L]]
  expect_true(grepl("UNIQUE(lob, grcode", sql, fixed = TRUE),
    info = "triangles UNIQUE constraint must include grcode")

  ata_sql <- DBI::dbGetQuery(con,
    "SELECT sql FROM sqlite_master WHERE type='table' AND name='ata_factors'"
  )$sql[[1L]]
  expect_true(grepl("UNIQUE(lob, grcode", ata_sql, fixed = TRUE),
    info = "ata_factors UNIQUE constraint must include grcode")
})

test_that("migrate_schema upgrades old triangles/ata_factors schema", {
  db <- tempfile(fileext = ".db")
  on.exit(unlink(db))

  # Build the OLD schema (no grcode in UNIQUE) manually
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "
    CREATE TABLE triangles (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      lob TEXT NOT NULL,
      accident_year INTEGER NOT NULL,
      development_lag INTEGER NOT NULL,
      cumulative_paid_loss REAL,
      cumulative_incurred_loss REAL,
      earned_premium REAL,
      UNIQUE(lob, accident_year, development_lag)
    )
  ")
  DBI::dbExecute(con, "ALTER TABLE triangles ADD COLUMN grcode INTEGER")
  DBI::dbExecute(con, "
    CREATE TABLE ata_factors (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      lob TEXT NOT NULL,
      accident_year INTEGER NOT NULL,
      from_lag INTEGER NOT NULL,
      to_lag INTEGER NOT NULL,
      ata_paid REAL,
      ata_incurred REAL,
      UNIQUE(lob, accident_year, from_lag, to_lag)
    )
  ")
  DBI::dbExecute(con, "ALTER TABLE ata_factors ADD COLUMN grcode INTEGER")

  # Insert one row of data that should survive migration
  DBI::dbExecute(con, "INSERT INTO triangles
    (lob, grcode, accident_year, development_lag, cumulative_paid_loss,
     cumulative_incurred_loss, earned_premium)
    VALUES ('WC', 100, 1988, 1, 200, 220, 500)")

  migrate_schema(con)

  # New schema must have grcode in UNIQUE
  tri_sql <- DBI::dbGetQuery(con,
    "SELECT sql FROM sqlite_master WHERE type='table' AND name='triangles'"
  )$sql[[1L]]
  expect_true(grepl("UNIQUE(lob, grcode", tri_sql, fixed = TRUE))

  ata_sql <- DBI::dbGetQuery(con,
    "SELECT sql FROM sqlite_master WHERE type='table' AND name='ata_factors'"
  )$sql[[1L]]
  expect_true(grepl("UNIQUE(lob, grcode", ata_sql, fixed = TRUE))

  # Existing data must be preserved
  rows <- DBI::dbGetQuery(con, "SELECT * FROM triangles")
  expect_equal(nrow(rows), 1L)
  expect_equal(rows$grcode, 100L)
})

test_that("two companies with same lob can coexist after schema fix", {
  db <- tempfile(fileext = ".db")
  on.exit(unlink(db))
  initialise_database(db)

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  make_rows <- function(grcode, grname) {
    data.frame(
      lob = "WC", grcode = grcode, grname = grname,
      accident_year = 1988:1997, development_lag = 1L,
      cumulative_paid_loss = runif(10, 100, 500),
      cumulative_incurred_loss = runif(10, 110, 550),
      earned_premium = 1000,
      stringsAsFactors = FALSE
    )
  }

  # Insert company A then company B — must not conflict
  DBI::dbWriteTable(con, "triangles", make_rows(101L, "Co A"), append = TRUE)
  expect_no_error(
    DBI::dbWriteTable(con, "triangles", make_rows(202L, "Co B"), append = TRUE)
  )

  all_rows <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM triangles")$n
  expect_equal(all_rows, 20L)
})

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
