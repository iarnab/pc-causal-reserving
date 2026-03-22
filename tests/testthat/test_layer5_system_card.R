# Tests for R/layer5_system_card.R
# Covers: initialise_system_card_schema, .score_data_integrity,
#         .score_transparency, .score_explainability, .score_accountability,
#         .score_reliability, record_attestation, compute_system_card,
#         format_system_card


# -- Helpers -------------------------------------------------------------------

# Returns a fresh in-memory SQLite connection with full schema
make_con <- function() {
  db  <- tempfile(fileext = ".db")
  initialise_database(db)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  initialise_system_card_schema(con)
  con
}


# -- initialise_system_card_schema --------------------------------------------

test_that("initialise_system_card_schema creates required tables", {
  db  <- tempfile(fileext = ".db")
  on.exit(unlink(db))
  initialise_database(db)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  initialise_system_card_schema(con)
  tables <- DBI::dbListTables(con)
  expect_true("system_card_attestations" %in% tables)
  expect_true("narrative_approvals"      %in% tables)
})

test_that("initialise_system_card_schema is idempotent", {
  db  <- tempfile(fileext = ".db")
  on.exit(unlink(db))
  initialise_database(db)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  expect_no_error(initialise_system_card_schema(con))
  expect_no_error(initialise_system_card_schema(con))
})


# -- .score_data_integrity -----------------------------------------------------

test_that(".score_data_integrity returns 0 on empty DB", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))
  score <- actuarialcausalintelligence:::.score_data_integrity(con)
  expect_equal(score, 0)
})

test_that(".score_data_integrity awards points for triangles, CCD, narrative", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))

  # Seed 1000 triangle rows (max completeness = 40 pts)
  tri_df <- data.frame(
    lob = "WC", grcode = 100L, grname = "TestCo",
    accident_year = rep(1988L:1997L, each = 100L),
    development_lag = rep(1L:10L, times = 100L),
    cumulative_paid_loss = 100, cumulative_incurred_loss = 110, earned_premium = 500,
    stringsAsFactors = FALSE
  )
  DBI::dbWriteTable(con, "triangles", tri_df, append = TRUE)

  # Seed 1 CCD (40 pts) and 1 narrative (20 pts)
  DBI::dbExecute(con,
    "INSERT INTO causal_context_docs (sha256, lob, accident_year, ccd_xml)
     VALUES ('abc', 'WC', 1988, '<CCD/>')")
  DBI::dbExecute(con,
    "INSERT INTO narrative_registry
     (narrative_id, lob, accident_year, ccd_sha256, narrative_text)
     VALUES ('n1', 'WC', 1988, 'abc', 'text')")

  score <- actuarialcausalintelligence:::.score_data_integrity(con)
  expect_equal(score, 100)
})


# -- .score_transparency -------------------------------------------------------

test_that(".score_transparency returns 0 on empty DB", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))
  expect_equal(actuarialcausalintelligence:::.score_transparency(con), 0)
})

test_that(".score_transparency awards points for audit entries and CCD hashes", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))

  # 50 audit rows → full audit score (50 pts)
  for (i in seq_len(50L)) {
    DBI::dbExecute(con,
      glue::glue("INSERT INTO audit_log (event_type, layer, status)
                  VALUES ('ingest', 'layer1', 'success')"))
  }
  # 5 CCD rows with sha256 → full CCD score (50 pts)
  for (j in seq_len(5L)) {
    DBI::dbExecute(con,
      glue::glue("INSERT INTO causal_context_docs (sha256, lob, accident_year, ccd_xml)
                  VALUES ('sha{j}', 'WC', {1987L + j}, '<CCD/>')"))
  }

  score <- actuarialcausalintelligence:::.score_transparency(con)
  expect_equal(score, 100)
})


# -- .score_explainability -----------------------------------------------------

test_that(".score_explainability returns 0 when no CCDs exist", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))
  expect_equal(actuarialcausalintelligence:::.score_explainability(con), 0)
})

test_that(".score_explainability returns 100 when all CCDs have active_paths", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))

  DBI::dbExecute(con,
    "INSERT INTO causal_context_docs (sha256, lob, accident_year, ccd_xml)
     VALUES ('h1', 'WC', 1988, '<CCD><active_paths>x</active_paths></CCD>')")

  score <- actuarialcausalintelligence:::.score_explainability(con)
  expect_equal(score, 100)
})

test_that(".score_explainability is proportional", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))

  # 1 with paths, 1 without → 50%
  DBI::dbExecute(con,
    "INSERT INTO causal_context_docs (sha256, lob, accident_year, ccd_xml)
     VALUES ('h1', 'WC', 1988, '<CCD><active_paths>x</active_paths></CCD>')")
  DBI::dbExecute(con,
    "INSERT INTO causal_context_docs (sha256, lob, accident_year, ccd_xml)
     VALUES ('h2', 'WC', 1989, '<CCD/>')")

  score <- actuarialcausalintelligence:::.score_explainability(con)
  expect_equal(score, 50)
})


# -- .score_accountability -----------------------------------------------------

test_that(".score_accountability returns 0 with no narratives", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))
  expect_equal(actuarialcausalintelligence:::.score_accountability(con), 0)
})

test_that(".score_accountability scores RLHF rate + approval rate", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))

  # 1 narrative that is rated and approved
  DBI::dbExecute(con,
    "INSERT INTO narrative_registry
     (narrative_id, lob, accident_year, ccd_sha256, narrative_text, rating_accuracy)
     VALUES ('n1', 'WC', 1988, 'sha1', 'text', 5)")
  DBI::dbExecute(con,
    "INSERT INTO narrative_approvals (narrative_id, decision, reviewer, reviewed_at)
     VALUES ('n1', 'approved', 'actuary', datetime('now'))")

  score <- actuarialcausalintelligence:::.score_accountability(con)
  # 1/1 rated (60pts) + 1/1 approved (40pts) = 100
  expect_equal(score, 100)
})


# -- .score_reliability --------------------------------------------------------

test_that(".score_reliability returns 50 (neutral) when no api_call rows", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))
  expect_equal(actuarialcausalintelligence:::.score_reliability(con), 50)
})

test_that(".score_reliability returns 100 when all api_calls succeed", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))

  for (i in seq_len(5L)) {
    DBI::dbExecute(con,
      "INSERT INTO audit_log (event_type, layer, status)
       VALUES ('api_call', 'layer4', 'success')")
  }
  score <- actuarialcausalintelligence:::.score_reliability(con)
  expect_equal(score, 100)
})

test_that(".score_reliability returns 0 when all api_calls fail", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))

  for (i in seq_len(3L)) {
    DBI::dbExecute(con,
      "INSERT INTO audit_log (event_type, layer, status)
       VALUES ('api_call', 'layer4', 'error')")
  }
  score <- actuarialcausalintelligence:::.score_reliability(con)
  expect_equal(score, 0)
})


# -- record_attestation --------------------------------------------------------

test_that("record_attestation writes a row and returns an integer ID", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))

  id <- record_attestation(con, "data_integrity", 85, "actuary_1", "Looks good")
  expect_true(is.numeric(id) && id >= 1L)

  row <- DBI::dbGetQuery(con, "SELECT * FROM system_card_attestations WHERE id = ?",
                         list(id))
  expect_equal(nrow(row), 1L)
  expect_equal(row$pillar, "data_integrity")
  expect_equal(row$score,  85)
})

test_that("record_attestation errors on invalid pillar", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))
  expect_error(record_attestation(con, "invalid_pillar", 50))
})

test_that("record_attestation errors on score out of range", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))
  expect_error(record_attestation(con, "transparency", 101))
  expect_error(record_attestation(con, "transparency", -1))
})

test_that("record_attestation accepts all valid pillar names", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))

  pillars <- c("data_integrity", "transparency", "explainability",
                "accountability", "reliability")
  for (p in pillars) {
    expect_no_error(record_attestation(con, p, 75),
                    info = glue::glue("record_attestation failed for pillar '{p}'"))
  }
})


# -- compute_system_card -------------------------------------------------------

test_that("compute_system_card returns a 5-row data.frame", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))

  card <- compute_system_card(con)
  expect_true(is.data.frame(card))
  expect_equal(nrow(card), 5L)
  expect_true(all(c("pillar", "auto_score", "human_score",
                    "composite_score", "evidence_type") %in% names(card)))
})

test_that("compute_system_card composite equals auto_score when no attestation", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))

  card <- compute_system_card(con)
  # Without attestation, composite_score == auto_score for every row
  for (i in seq_len(nrow(card))) {
    expect_equal(card$composite_score[i], card$auto_score[i])
  }
})

test_that("compute_system_card applies 70/30 composite when attestation exists", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))

  record_attestation(con, "transparency", 80, "actuary_1")
  card <- compute_system_card(con)

  trans_row   <- card[card$pillar == "transparency", ]
  auto_s      <- trans_row$auto_score
  expected_c  <- round(0.70 * auto_s + 0.30 * 80, 1)
  expect_equal(trans_row$composite_score, expected_c)
})

test_that("compute_system_card evidence_type reflects attestation presence", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))

  record_attestation(con, "reliability", 90, "actuary_1")
  card <- compute_system_card(con)

  expect_equal(
    card$evidence_type[card$pillar == "reliability"],
    "Tested + Attestation"
  )
  expect_equal(
    card$evidence_type[card$pillar == "transparency"],
    "Tested (automated)"
  )
})


# -- format_system_card --------------------------------------------------------

test_that("format_system_card returns a non-empty character string", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))

  card <- compute_system_card(con)
  txt  <- format_system_card(card)
  expect_true(is.character(txt))
  expect_true(nzchar(txt))
})

test_that("format_system_card includes all 5 pillar labels", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))

  card <- compute_system_card(con)
  txt  <- format_system_card(card)

  for (label in c("Data Integrity", "Transparency", "Explainability",
                   "Accountability", "Reliability")) {
    expect_true(grepl(label, txt, fixed = TRUE),
                info = glue::glue("Missing pillar label '{label}' in formatted card"))
  }
})

test_that("format_system_card includes overall composite score", {
  con <- make_con()
  on.exit(DBI::dbDisconnect(con))

  card <- compute_system_card(con)
  txt  <- format_system_card(card)
  expect_true(grepl("Overall composite score", txt, fixed = TRUE))
})
