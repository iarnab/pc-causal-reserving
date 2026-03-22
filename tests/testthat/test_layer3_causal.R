test_that("build_reserving_dag returns a dagitty object", {
  dag <- build_reserving_dag()
  expect_s3_class(dag, "dagitty")
})

test_that("all 5 layers have at least one node in the DAG", {
  dag   <- build_reserving_dag()
  nodes <- get_reserving_dag_nodes()
  dag_node_names <- names(dagitty::coordinates(dag)$x)

  for (layer in names(nodes)) {
    layer_nodes <- nodes[[layer]]
    expect_true(
      any(layer_nodes %in% dag_node_names),
      info = glue::glue("Layer {layer} has no nodes in the DAG")
    )
  }
})

test_that("get_dag_paths returns non-empty result for L1 -> L5", {
  dag   <- build_reserving_dag()
  paths <- get_dag_paths(dag, "medical_cpi", "ultimate_loss")
  expect_true(nrow(paths) >= 1L)
  expect_true("paths" %in% names(paths))
})

test_that("get_dag_paths returns empty data.frame for non-existent path", {
  dag   <- build_reserving_dag()
  # ultimate_loss does not cause medical_cpi (reverse direction)
  paths <- get_dag_paths(dag, "ultimate_loss", "medical_cpi")
  expect_equal(nrow(paths), 0L)
})

test_that("query_do_calculus returns a list with required fields", {
  dag    <- build_reserving_dag()
  result <- query_do_calculus(dag, "tort_reform", "ultimate_loss")
  expect_true(is.list(result))
  expect_true(all(c("adjustment_set","paths","identifiable") %in% names(result)))
  expect_true(is.logical(result$identifiable))
  expect_true(is.character(result$adjustment_set))
})

test_that("extract_active_subgraph returns nodes and edges", {
  dag    <- build_reserving_dag()
  result <- extract_active_subgraph(dag, c("medical_cpi", "tort_reform"))
  expect_true(is.list(result))
  expect_true(all(c("nodes","edges") %in% names(result)))
  expect_true(length(result$nodes) >= 2L)
})

# -- generate_ccd (end-to-end orchestrator) ------------------------------------

test_that("generate_ccd returns a valid XML string and registers in DB", {
  db <- tempfile(fileext = ".db")
  on.exit(unlink(db))
  initialise_database(db)

  dag <- build_reserving_dag()
  anomaly_df <- data.frame(
    rule_id      = "ATA_ZSCORE",
    severity     = "warning",
    lob          = "WC",
    accident_year = 1993L,
    observed     = 1.15,
    expected     = 1.02,
    message      = "ATA exceeds 2 sigma",
    stringsAsFactors = FALSE
  )

  xml_str <- generate_ccd(dag, anomaly_df, "WC", 1993L, db)
  expect_true(is.character(xml_str))
  expect_true(nzchar(xml_str))

  # Must be parseable XML
  doc <- xml2::read_xml(xml_str)
  expect_equal(xml2::xml_name(doc), "CausalContextDocument")

  # Must be registered in DB
  con  <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  rows <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM causal_context_docs")
  expect_equal(rows$n, 1L)
})

test_that("generate_ccd with no anomalies defaults to development_factor node", {
  db <- tempfile(fileext = ".db")
  on.exit(unlink(db))
  initialise_database(db)

  dag        <- build_reserving_dag()
  empty_anom <- data.frame(
    rule_id      = character(0), severity = character(0),
    lob          = character(0), accident_year = integer(0),
    observed     = numeric(0),  expected     = numeric(0),
    message      = character(0), stringsAsFactors = FALSE
  )

  xml_str <- generate_ccd(dag, empty_anom, "WC", 1993L, db)
  expect_true(grepl("development_factor", xml_str, fixed = TRUE))
})

test_that("generate_ccd with DIAGONAL_EFFECT flags ibnr_emergence node", {
  db <- tempfile(fileext = ".db")
  on.exit(unlink(db))
  initialise_database(db)

  dag <- build_reserving_dag()
  anomaly_df <- data.frame(
    rule_id      = "DIAGONAL_EFFECT",
    severity     = "warning",
    lob          = "WC",
    accident_year = 1993L,
    observed     = 0.08,
    expected     = 0.01,
    message      = "Diagonal effect detected",
    stringsAsFactors = FALSE
  )

  xml_str <- generate_ccd(dag, anomaly_df, "WC", 1993L, db)
  expect_true(grepl("ibnr_emergence", xml_str, fixed = TRUE))
})

test_that("generate_ccd with evidence_nodes embeds evidence in XML", {
  db <- tempfile(fileext = ".db")
  on.exit(unlink(db))
  initialise_database(db)

  dag        <- build_reserving_dag()
  empty_anom <- data.frame(
    rule_id = character(0), severity = character(0), lob = character(0),
    accident_year = integer(0), observed = numeric(0), expected = numeric(0),
    message = character(0), stringsAsFactors = FALSE
  )
  evidence <- list(medical_cpi = 4.2, gdp_growth = -1.1)

  xml_str <- generate_ccd(dag, empty_anom, "WC", 1993L, db, evidence_nodes = evidence)
  expect_true(grepl("medical_cpi", xml_str, fixed = TRUE))
  expect_true(grepl("4.2", xml_str, fixed = TRUE))
})

test_that("generate_ccd is idempotent: calling twice does not duplicate DB row", {
  db <- tempfile(fileext = ".db")
  on.exit(unlink(db))
  initialise_database(db)

  dag <- build_reserving_dag()
  anomaly_df <- data.frame(
    rule_id = character(0), severity = character(0), lob = character(0),
    accident_year = integer(0), observed = numeric(0), expected = numeric(0),
    message = character(0), stringsAsFactors = FALSE
  )

  generate_ccd(dag, anomaly_df, "WC", 1993L, db)
  generate_ccd(dag, anomaly_df, "WC", 1993L, db)

  con  <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  rows <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM causal_context_docs")
  expect_equal(rows$n, 1L)   # INSERT OR IGNORE deduplicates by sha256
})
