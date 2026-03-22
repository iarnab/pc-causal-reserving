test_that("compute_sha256 returns a 64-character hex string", {
  hash <- compute_sha256("test string")
  expect_equal(nchar(hash), 64L)
  expect_match(hash, "^[0-9a-f]{64}$")
})

test_that("compute_sha256 is deterministic", {
  expect_equal(compute_sha256("abc"), compute_sha256("abc"))
})

test_that("build_ccd_xml produces well-formed XML", {
  subgraph <- list(
    nodes = c("medical_cpi", "avg_case_value", "case_reserve_opening", "ultimate_loss"),
    edges = data.frame(
      from = c("medical_cpi", "avg_case_value", "case_reserve_opening"),
      to   = c("avg_case_value", "case_reserve_opening", "ultimate_loss"),
      stringsAsFactors = FALSE
    )
  )
  anomaly_df <- data.frame(
    rule_id  = "ATA_ZSCORE",
    severity = "warning",
    observed = 2.5,
    expected = 1.5,
    message  = "Test anomaly",
    stringsAsFactors = FALSE
  )
  evidence <- list(medical_cpi = 4.2, gdp_growth = -1.1)

  xml_str <- build_ccd_xml(subgraph, anomaly_df, evidence, "WC", 1993L,
                             "P(ultimate_loss | do(tort_reform=0))")
  expect_true(nzchar(xml_str))

  # Parse and validate as XML
  doc <- xml2::read_xml(xml_str)
  expect_equal(xml2::xml_name(doc), "CausalContextDocument")

  # Check required child elements
  child_names <- xml2::xml_name(xml2::xml_children(doc))
  expect_true(all(c("Metadata","CausalSubgraph","AnomalyContext",
                    "EvidenceNodes","DoCalculusQuery") %in% child_names))
})

test_that("register_ccd writes to DB and is idempotent", {
  db <- tempfile(fileext = ".db")
  on.exit(unlink(db))
  initialise_database(db)

  ccd_xml <- "<CausalContextDocument><Metadata></Metadata></CausalContextDocument>"
  sha     <- compute_sha256(ccd_xml)

  expect_no_error(register_ccd(db, sha, ccd_xml, "WC", 1993L))
  expect_no_error(register_ccd(db, sha, ccd_xml, "WC", 1993L))  # idempotent

  con  <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  rows <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM causal_context_docs")
  expect_equal(rows$n, 1L)
})

test_that("CCD SHA-256 round-trip: generate, register, retrieve", {
  db <- tempfile(fileext = ".db")
  on.exit(unlink(db))
  initialise_database(db)

  ccd_xml <- "<CausalContextDocument><Metadata></Metadata></CausalContextDocument>"
  sha     <- compute_sha256(ccd_xml)
  register_ccd(db, sha, ccd_xml, "WC", 1993L)

  con     <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  row     <- DBI::dbGetQuery(con, glue::glue("SELECT sha256, ccd_xml FROM causal_context_docs WHERE sha256 = '{sha}'"))
  expect_equal(nrow(row), 1L)
  expect_equal(row$sha256, sha)
  expect_equal(compute_sha256(row$ccd_xml), sha)
})
