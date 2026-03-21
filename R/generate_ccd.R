# ==============================================================================
# R/layer_4_ccd/generate_ccd.R
# Causal Context Document (CCD) Generator
#
# The CCD is the core architectural innovation of this research: a structured
# XML document injected into every LLM prompt, transforming raw triangle data
# into causally pre-processed context. Each CCD is registered with a SHA-256
# hash for full auditability.
#
# CCD XML Schema:
#   <CausalContextDocument>
#     <Metadata>           lob, accident_year, generated_at
#     <CausalSubgraph>     nodes and edges from the active causal pathway
#     <AnomalyContext>     flagged development periods with Z-scores
#     <EvidenceNodes>      observed values for conditioning variables
#     <DoCalculusQuery>    intervention query specification
#   </CausalContextDocument>
#
# Required packages: xml2, digest, DBI, RSQLite, glue
# Do NOT call library() here — loaded by app.R.
#
# Usage:
#   source("R/layer_4_ccd/generate_ccd.R")
#   ccd_xml <- generate_ccd(dag, anomaly_df, ata_df, "WC", 1993L, db_path)
# ==============================================================================


# -- CCD XML construction ------------------------------------------------------

#' Build the CCD XML document
#'
#' Constructs the Causal Context Document as an xml2 document. Returns the
#' serialised XML string.
#'
#' @param causal_subgraph List with elements \code{nodes} (character) and
#'   \code{edges} (data.frame with columns from, to). From extract_active_subgraph().
#' @param anomaly_context data.frame of anomaly flags for this (lob, accident_year).
#'   Columns: rule_id, severity, observed, expected, message.
#' @param evidence_nodes  Named list of node name -> observed value for L1/L2
#'   conditioning variables (e.g. list(medical_cpi = 4.2, gdp_growth = -1.1)).
#' @param lob             Character: line of business.
#' @param accident_year   Integer: accident year.
#' @param do_query_spec   Character: the do-calculus query in plain text, e.g.
#'   "P(ultimate_loss | do(tort_reform = 0), evidence)".
#' @return Character scalar: serialised XML string.
build_ccd_xml <- function(causal_subgraph, anomaly_context, evidence_nodes,
                           lob, accident_year, do_query_spec = "") {
  stopifnot(is.list(causal_subgraph),
            is.data.frame(anomaly_context),
            is.list(evidence_nodes),
            is.character(lob), length(lob) == 1L,
            is.integer(accident_year), length(accident_year) == 1L)

  doc  <- xml2::xml_new_root("CausalContextDocument")

  # <Metadata>
  meta <- xml2::xml_add_child(doc, "Metadata")
  xml2::xml_add_child(meta, "LOB",          lob)
  xml2::xml_add_child(meta, "AccidentYear", as.character(accident_year))
  xml2::xml_add_child(meta, "GeneratedAt",  format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"))
  xml2::xml_add_child(meta, "Schema",       "CCD-v1.0")

  # <CausalSubgraph>
  subgraph_el <- xml2::xml_add_child(doc, "CausalSubgraph")
  nodes_el    <- xml2::xml_add_child(subgraph_el, "Nodes")
  for (n in causal_subgraph$nodes) {
    xml2::xml_add_child(nodes_el, "Node", n)
  }
  edges_el <- xml2::xml_add_child(subgraph_el, "Edges")
  if (nrow(causal_subgraph$edges) > 0L) {
    for (i in seq_len(nrow(causal_subgraph$edges))) {
      e_el <- xml2::xml_add_child(edges_el, "Edge")
      xml2::xml_set_attr(e_el, "from", causal_subgraph$edges$from[[i]])
      xml2::xml_set_attr(e_el, "to",   causal_subgraph$edges$to[[i]])
    }
  }

  # <AnomalyContext>
  anomaly_el <- xml2::xml_add_child(doc, "AnomalyContext")
  for (i in seq_len(nrow(anomaly_context))) {
    flag_el <- xml2::xml_add_child(anomaly_el, "AnomalyFlag")
    xml2::xml_set_attr(flag_el, "rule_id",  anomaly_context$rule_id[[i]])
    xml2::xml_set_attr(flag_el, "severity", anomaly_context$severity[[i]])
    xml2::xml_add_child(flag_el, "Observed", as.character(anomaly_context$observed[[i]]))
    xml2::xml_add_child(flag_el, "Expected", as.character(anomaly_context$expected[[i]]))
    xml2::xml_add_child(flag_el, "Message",  anomaly_context$message[[i]])
  }

  # <EvidenceNodes>
  evidence_el <- xml2::xml_add_child(doc, "EvidenceNodes")
  for (nm in names(evidence_nodes)) {
    ev_el <- xml2::xml_add_child(evidence_el, "Evidence")
    xml2::xml_set_attr(ev_el, "node",  nm)
    xml2::xml_set_attr(ev_el, "value", as.character(evidence_nodes[[nm]]))
  }

  # <DoCalculusQuery>
  query_el <- xml2::xml_add_child(doc, "DoCalculusQuery")
  xml2::xml_add_child(query_el, "QueryText", do_query_spec)

  as.character(doc)
}


# -- SHA-256 audit -------------------------------------------------------------

#' Compute the SHA-256 hash of a CCD XML string
#'
#' @param ccd_xml_string Character scalar: the serialised CCD XML.
#' @return Character scalar: 64-character lowercase hex SHA-256 digest.
compute_sha256 <- function(ccd_xml_string) {
  stopifnot(is.character(ccd_xml_string), length(ccd_xml_string) == 1L)
  digest::digest(ccd_xml_string, algo = "sha256", serialize = FALSE)
}


#' Register a CCD in the audit registry
#'
#' Writes a row to the causal_context_docs table. Uses INSERT OR IGNORE so
#' identical CCDs (same SHA-256) are not duplicated.
#'
#' @param db_path      Character: path to the SQLite database.
#' @param ccd_sha256   Character: SHA-256 hash from compute_sha256().
#' @param ccd_xml      Character: serialised CCD XML.
#' @param lob          Character: line of business.
#' @param accident_year Integer: accident year.
#' @return Invisible NULL.
register_ccd <- function(db_path, ccd_sha256, ccd_xml, lob, accident_year) {
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con,
    "INSERT OR IGNORE INTO causal_context_docs (sha256, lob, accident_year, ccd_xml)
     VALUES (?, ?, ?, ?)",
    list(ccd_sha256, lob, as.integer(accident_year), ccd_xml)
  )

  invisible(NULL)
}


# -- Main orchestrator ---------------------------------------------------------

#' Generate a Causal Context Document for a given (lob, accident_year)
#'
#' End-to-end: extract active subgraph from anomaly flags -> build XML ->
#' compute SHA-256 -> register in DB -> return XML string.
#'
#' @param dag           dagitty DAG from build_reserving_dag().
#' @param anomaly_df    data.frame of all anomaly flags (from combine_anomaly_signals()).
#' @param lob           Character: line of business.
#' @param accident_year Integer: accident year.
#' @param db_path       Character: SQLite DB path.
#' @param evidence_nodes Named list of external evidence (optional).
#' @return Character scalar: the CCD XML string.
generate_ccd <- function(dag, anomaly_df, lob, accident_year,
                          db_path, evidence_nodes = list()) {
  stopifnot(inherits(dag, "dagitty"),
            is.data.frame(anomaly_df),
            is.character(lob),
            is.integer(accident_year))

  # Filter anomalies for this accident year
  ay_anomalies <- anomaly_df[
    !is.na(anomaly_df$accident_year) &
    anomaly_df$lob == lob &
    anomaly_df$accident_year == accident_year, ]

  # Determine flagged DAG nodes from anomaly rule types
  flagged_nodes <- character(0L)
  if (any(ay_anomalies$rule_id == "ATA_ZSCORE")) {
    flagged_nodes <- c(flagged_nodes, "case_reserve_opening", "development_factor")
  }
  if (any(ay_anomalies$rule_id == "DIAGONAL_EFFECT")) {
    flagged_nodes <- c(flagged_nodes, "ibnr_emergence")
  }
  if (length(flagged_nodes) == 0L) {
    flagged_nodes <- c("development_factor")
  }

  subgraph     <- extract_active_subgraph(dag, flagged_nodes)
  do_query_str <- glue::glue(
    "P(ultimate_loss | do(case_reserve_opening = adequately_reserved), evidence) ",
    "for {lob} AY{accident_year}"
  )

  ccd_xml  <- build_ccd_xml(subgraph, ay_anomalies, evidence_nodes,
                              lob, accident_year, do_query_str)
  sha256   <- compute_sha256(ccd_xml)
  register_ccd(db_path, sha256, ccd_xml, lob, accident_year)

  ccd_xml
}
