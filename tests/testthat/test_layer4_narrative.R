test_that("synthesize_reserve_narrative with dry_run=TRUE returns non-empty string", {
  ccd_xml <- paste0(
    "<CausalContextDocument>",
    "<Metadata><LOB>WC</LOB><AccidentYear>1993</AccidentYear></Metadata>",
    "</CausalContextDocument>"
  )
  result <- synthesize_reserve_narrative(ccd_xml, "WC", 1993L, dry_run = TRUE)
  expect_true(is.character(result))
  expect_true(nzchar(result))
  expect_match(result, "WC")
  expect_match(result, "1993")
})

test_that("synthesize_reserve_narrative dry_run does not call API", {
  # This test verifies no API key is needed in dry_run mode
  old_key <- Sys.getenv("ANTHROPIC_API_KEY")
  Sys.setenv(ANTHROPIC_API_KEY = "")
  on.exit(Sys.setenv(ANTHROPIC_API_KEY = old_key), add = TRUE)

  ccd_xml <- "<CausalContextDocument></CausalContextDocument>"
  expect_no_error(
    synthesize_reserve_narrative(ccd_xml, "WC", 1993L, dry_run = TRUE)
  )
})

test_that("build_reserve_narrative_prompt returns non-empty string with CCD embedded", {
  ccd_xml <- "<CausalContextDocument><Metadata></Metadata></CausalContextDocument>"
  prompt  <- build_reserve_narrative_prompt(ccd_xml, "WC", 1993L)
  expect_true(is.character(prompt))
  expect_true(nzchar(prompt))
  expect_match(prompt, "WC")
  expect_match(prompt, "1993")
  expect_match(prompt, "CAUSAL ATTRIBUTION")
  expect_match(prompt, "RESERVE NARRATIVE")
  expect_match(prompt, "COUNTERFACTUAL")
})

test_that("collect_rlhf_feedback writes correct row to DB", {
  db <- tempfile(fileext = ".db")
  on.exit(unlink(db))
  initialise_database(db)

  collect_rlhf_feedback(
    narrative_id   = "test_narrative_001",
    lob            = "WC",
    accident_year  = 1993L,
    ccd_sha256     = "abc123",
    narrative_text = "Test narrative text",
    ratings        = list(accuracy=4L, coherence=4L, tone=5L,
                          completeness=3L, conciseness=4L),
    reviewer_id    = "actuary_1",
    reviewer_notes = "Good narrative",
    db_path        = db
  )

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  row <- DBI::dbGetQuery(con,
    "SELECT * FROM narrative_registry WHERE narrative_id = 'test_narrative_001'"
  )
  expect_equal(nrow(row), 1L)
  expect_equal(row$lob, "WC")
  expect_equal(row$accident_year, 1993L)
  expect_equal(row$rating_accuracy, 4L)
  expect_equal(row$reviewer_id, "actuary_1")
})
