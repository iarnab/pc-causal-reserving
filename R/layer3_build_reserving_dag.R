# ==============================================================================
# R/layer_3_causal/build_reserving_dag.R
# P&C Loss Reserving Causal DAG
#
# Defines the 5-layer causal DAG for the loss development process as a
# dagitty object. Provides path queries and do-calculus wrappers.
# This file contains ONLY model definitions — no DB I/O, no library() calls.
#
# Causal story (see inst/dag/reserving_dag.txt for full edge justifications):
#   L1 Exogenous Shocks  -> L2 Exposure & Mix Shifts
#   L2 Exposure          -> L3 Claim Frequency & Severity
#   L3 Claim F&S         -> L4 Case Reserve Adequacy
#   L4 Reserve Adequacy  -> L5 Development Factors & Ultimates
#
# Required packages: dagitty
# Do NOT call library() here — loaded by app.R.
#
# Usage:
#   source("R/layer_3_causal/build_reserving_dag.R")
#   dag   <- build_reserving_dag()
#   nodes <- get_reserving_dag_nodes()
#   paths <- get_dag_paths(dag, "medical_cpi", "ultimate_loss")
#   adj   <- query_do_calculus(dag, "tort_reform", "ultimate_loss")
# ==============================================================================


# -- DAG construction ----------------------------------------------------------

#' Build the 5-layer P&C loss reserving causal DAG
#'
#' Encodes the loss development process as a dagitty DAG. Node names match
#' the macro and claims variables used in the Causal Context Document (CCD).
#' All edges point from cause to effect (upstream -> downstream).
#'
#' @return A dagitty DAG object.
build_reserving_dag <- function() {
  dag_file <- system.file("dag/reserving_dag.txt", package = "actuarialcausalintelligence")
  if (!nzchar(dag_file)) {
    dag_file <- file.path(here::here(), "inst", "dag", "reserving_dag.txt")
  }
  dag_spec <- paste(readLines(dag_file, warn = FALSE), collapse = "\n")

  # Strip comment lines (lines starting with #) before passing to dagitty
  dag_lines <- strsplit(dag_spec, "\n")[[1L]]
  dag_lines <- dag_lines[!grepl("^\\s*#", dag_lines)]
  clean_spec <- paste(dag_lines, collapse = "\n")

  dagitty::dagitty(clean_spec)
}


# -- Node catalogue ------------------------------------------------------------

#' Return all DAG node names grouped by layer
#'
#' Returns a named list where each element is a character vector of node
#' names at that layer. Used for display, looping, and CCD construction.
#'
#' @return Named list with elements: l1_exogenous, l2_exposure, l3_claim,
#'   l4_reserve, l5_ultimate.
get_reserving_dag_nodes <- function() {
  list(
    l1_exogenous = c("gdp_growth", "unemployment_rate",
                     "tort_reform", "medical_cpi"),
    l2_exposure  = c("payroll_growth", "demographic_shift", "earned_premium"),
    l3_claim     = c("claim_frequency", "reported_claims",
                     "avg_case_value", "alae_ratio"),
    l4_reserve   = c("case_reserve_opening", "ibnr_emergence"),
    l5_ultimate  = c("development_factor", "tail_factor",
                     "ultimate_loss", "loss_ratio")
  )
}


# -- Path queries --------------------------------------------------------------

#' Return all directed paths between two nodes in the reserving DAG
#'
#' Thin wrapper around dagitty::paths() returning only directed (active)
#' causal paths. Returns a zero-row data.frame if no directed path exists.
#'
#' @param dag  A dagitty DAG object from build_reserving_dag().
#' @param from Character scalar: starting node name.
#' @param to   Character scalar: ending node name.
#' @return A data.frame with column \code{paths} (character), one row per path.
get_dag_paths <- function(dag, from, to) {
  stopifnot(inherits(dag, "dagitty"),
            is.character(from), length(from) == 1L,
            is.character(to),   length(to)   == 1L)

  result <- dagitty::paths(dag, from = from, to = to, directed = TRUE)

  if (length(result$paths) == 0L) {
    message(glue::glue("No directed path from '{from}' to '{to}' in reserving DAG."))
    return(data.frame(paths = character(0L)))
  }

  data.frame(paths = result$paths, stringsAsFactors = FALSE)
}


# -- Do-calculus queries -------------------------------------------------------

#' Query the minimal adjustment set for a causal intervention
#'
#' Returns the minimal set of variables to condition on to identify the
#' causal effect P(outcome | do(intervention)) from observational data,
#' using dagitty's backdoor adjustment set algorithm.
#'
#' @param dag               A dagitty DAG from build_reserving_dag().
#' @param intervention_node Character scalar: the intervened-upon node.
#' @param outcome_node      Character scalar: the outcome node.
#' @return A list with:
#'   \item{adjustment_set}{Character vector of variables to adjust for.}
#'   \item{paths}{data.frame of directed paths from intervention to outcome.}
#'   \item{identifiable}{Logical: TRUE if the effect is non-parametrically identifiable.}
query_do_calculus <- function(dag, intervention_node, outcome_node) {
  stopifnot(inherits(dag, "dagitty"),
            is.character(intervention_node), length(intervention_node) == 1L,
            is.character(outcome_node),      length(outcome_node)      == 1L)

  adj_sets <- tryCatch(
    dagitty::adjustmentSets(dag,
                             exposure = intervention_node,
                             outcome  = outcome_node,
                             type     = "minimal"),
    error = function(e) {
      warning(glue::glue(
        "query_do_calculus: adjustmentSets failed: {conditionMessage(e)}"
      ))
      list()
    }
  )

  identifiable <- length(adj_sets) > 0L
  adj_vector   <- if (identifiable) as.character(adj_sets[[1L]]) else character(0L)

  list(
    adjustment_set = adj_vector,
    paths          = get_dag_paths(dag, intervention_node, outcome_node),
    identifiable   = identifiable
  )
}


# -- Subgraph extraction -------------------------------------------------------

#' Extract the active causal subgraph for a set of flagged nodes
#'
#' Returns the nodes and edges of the DAG that lie on any directed path
#' from any flagged node to ultimate_loss. Used by the CCD generator to
#' include only relevant causal context in the LLM prompt.
#'
#' @param dag           A dagitty DAG from build_reserving_dag().
#' @param flagged_nodes Character vector: nodes flagged by the anomaly detector.
#' @return A list with elements \code{nodes} (character vector) and
#'   \code{edges} (data.frame with columns from, to).
extract_active_subgraph <- function(dag, flagged_nodes) {
  stopifnot(inherits(dag, "dagitty"), is.character(flagged_nodes))

  all_nodes <- character(0L)
  all_edges <- data.frame(from = character(), to = character(),
                           stringsAsFactors = FALSE)

  for (node in flagged_nodes) {
    paths_df <- get_dag_paths(dag, from = node, to = "ultimate_loss")
    if (nrow(paths_df) == 0L) next

    for (path_str in paths_df$paths) {
      path_nodes <- trimws(strsplit(path_str, "->")[[1L]])
      all_nodes  <- union(all_nodes, path_nodes)
      if (length(path_nodes) >= 2L) {
        edges <- data.frame(
          from = path_nodes[-length(path_nodes)],
          to   = path_nodes[-1L],
          stringsAsFactors = FALSE
        )
        all_edges <- unique(rbind(all_edges, edges))
      }
    }
  }

  list(nodes = all_nodes, edges = all_edges)
}
