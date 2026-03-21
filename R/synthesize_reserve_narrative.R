# ==============================================================================
# R/layer_5_llm/synthesize_reserve_narrative.R
# Reserve Narrative Synthesis & RLHF Feedback Collection
#
# Builds structured prompts from Causal Context Documents (CCDs) and
# calls the Claude API to generate reserve narratives. Collects RLHF
# feedback from FCAS-credentialed actuaries via the Shiny dashboard.
#
# Required packages: glue, DBI, RSQLite
# Do NOT call library() here — loaded by app.R.
#
# Usage:
#   source("R/layer_5_llm/synthesize_reserve_narrative.R")
#   narrative <- synthesize_reserve_narrative(ccd_xml, "WC", 1993L)
#   collect_rlhf_feedback("narrative_001", rating_list, "actuary_1",
#                         "Notes here", db_path)
# ==============================================================================


# -- System prompt -------------------------------------------------------------

RESERVE_SYSTEM_PROMPT <- paste0(
  "You are an expert P&C reserve actuary with 20 years of experience in ",
  "Workers Compensation loss reserving. You analyse Schedule P development ",
  "data and provide clear, professional reserve narratives for a technical ",
  "actuarial audience (ACAS/FCAS level). ",
  "You reason causally: when development deviates from expectation, you ",
  "identify the upstream drivers (macro environment, claims operations, ",
  "case reserve adequacy) rather than simply describing the pattern. ",
  "Be precise, use actuarial terminology, and always acknowledge uncertainty. ",
  "Do not reproduce the raw input data verbatim."
)


# -- Prompt builder ------------------------------------------------------------

#' Build the user-turn prompt for reserve narrative synthesis
#'
#' Embeds the CCD XML as structured context and requests a three-section
#' reserve narrative.
#'
#' @param ccd_xml       Character scalar: serialised CCD XML from generate_ccd().
#' @param lob           Character scalar: line of business.
#' @param accident_year Integer: accident year.
#' @return Character scalar: the full user prompt.
build_reserve_narrative_prompt <- function(ccd_xml, lob, accident_year) {
  stopifnot(is.character(ccd_xml), nzchar(ccd_xml),
            is.character(lob),
            is.integer(accident_year))

  glue::glue(
    "The following Causal Context Document (CCD) encodes the detected ",
    "anomalies and causal structure for {lob} Accident Year {accident_year}:\n\n",
    "<CCD>\n{ccd_xml}\n</CCD>\n\n",
    "Based on the causal subgraph and anomaly context above, provide the ",
    "following three sections:\n\n",
    "1. CAUSAL ATTRIBUTION (3-4 sentences): Which upstream causal nodes ",
    "(from Layer 1 or Layer 2 of the DAG) best explain the observed ",
    "development deviation? Cite specific nodes from the CausalSubgraph ",
    "and their quantified values from EvidenceNodes where available.\n\n",
    "2. RESERVE NARRATIVE (4-6 sentences): A professional reserve narrative ",
    "describing the development pattern, its causal drivers, and the implied ",
    "IBNR posture. Include uncertainty language appropriate for a Statement ",
    "of Actuarial Opinion.\n\n",
    "3. COUNTERFACTUAL SCENARIO (2-3 sentences): Address the DoCalculusQuery ",
    "from the CCD — what would the development pattern look like under the ",
    "specified intervention? Use do-calculus language (e.g. 'under do(X=x)')."
  )
}


# -- Narrative synthesis -------------------------------------------------------

#' Synthesize a reserve narrative from a CCD
#'
#' Calls the Claude API with the CCD-grounded prompt and returns the
#' generated narrative. Supports dry_run = TRUE for testing without API calls.
#'
#' @param ccd_xml       Character scalar: serialised CCD XML.
#' @param lob           Character: line of business.
#' @param accident_year Integer: accident year.
#' @param max_tokens    Integer: max response tokens (default 1024).
#' @param dry_run       Logical: if TRUE, returns a placeholder without API call.
#' @return Character scalar: the generated narrative, or NULL on API failure.
synthesize_reserve_narrative <- function(ccd_xml, lob, accident_year,
                                          max_tokens = 1024L, dry_run = FALSE) {
  stopifnot(is.character(ccd_xml), is.character(lob),
            is.integer(accident_year), is.logical(dry_run))

  if (dry_run) {
    return(glue::glue(
      "[DRY RUN] Reserve narrative for {lob} AY{accident_year}. ",
      "CCD SHA-256: {compute_sha256(ccd_xml)}"
    ))
  }

  prompt <- build_reserve_narrative_prompt(ccd_xml, lob, accident_year)

  call_claude(
    messages      = list(list(role = "user", content = prompt)),
    system_prompt = RESERVE_SYSTEM_PROMPT,
    max_tokens    = as.integer(max_tokens),
    temperature   = 0
  )
}


# -- RLHF feedback collection --------------------------------------------------

#' Record actuary RLHF feedback for a narrative
#'
#' Writes a structured feedback record to the narrative_registry table.
#' Called by the Shiny RLHF Review tab on submit.
#'
#' @param narrative_id     Character: unique identifier for this narrative.
#' @param lob              Character: line of business.
#' @param accident_year    Integer: accident year.
#' @param ccd_sha256       Character: SHA-256 of the CCD used.
#' @param narrative_text   Character: the narrative text being rated.
#' @param ratings          Named integer list with elements: accuracy, coherence,
#'   tone, completeness, conciseness. Each in 1-5.
#' @param reviewer_id      Character: actuary identifier.
#' @param reviewer_notes   Character: free-text notes (may be empty).
#' @param db_path          Character: SQLite DB path.
#' @return Invisible NULL.
collect_rlhf_feedback <- function(narrative_id, lob, accident_year, ccd_sha256,
                                   narrative_text, ratings, reviewer_id,
                                   reviewer_notes = "", db_path) {
  stopifnot(
    is.character(narrative_id), nzchar(narrative_id),
    is.character(lob),
    is.integer(accident_year),
    is.list(ratings),
    all(c("accuracy","coherence","tone","completeness","conciseness") %in% names(ratings))
  )

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT OR REPLACE INTO narrative_registry
     (narrative_id, lob, accident_year, ccd_sha256, narrative_text,
      reviewer_id, rating_accuracy, rating_coherence, rating_tone,
      rating_completeness, rating_conciseness, reviewer_notes)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    list(
      narrative_id,
      lob,
      as.integer(accident_year),
      ccd_sha256,
      narrative_text,
      reviewer_id,
      as.integer(ratings$accuracy),
      as.integer(ratings$coherence),
      as.integer(ratings$tone),
      as.integer(ratings$completeness),
      as.integer(ratings$conciseness),
      reviewer_notes
    )
  )

  invisible(NULL)
}
