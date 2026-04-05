# ==============================================================================
# R/run_layer3_statefarm_wc_ccds.R
# Layer 3 CCD Pipeline — State Farm WC, Accident Years 1998-2007
#
# For each accident year, this script:
#   1. Pulls the full ATA/triangle data for State Farm WC (grcode 1767)
#   2. Runs Layer 2 anomaly detection (Z-score + diagonal)
#   3. Persists anomaly flags to anomaly_flags table
#   4. Derives triangle-based evidence values (case_reserve_opening,
#      development_factor, ultimate_loss) from the chain-ladder
#   5. Merges with macro CSV (medical_cpi, gdp_growth, etc.)
#   6. Calls extract_active_subgraph() using detected flagged DAG nodes,
#      augmented with the State Farm key causal path:
#        medical_cpi -> avg_case_value -> case_reserve_opening
#        -> development_factor -> ultimate_loss
#   7. Calls build_ccd_xml() with fully-populated <EvidenceNodes>
#   8. Calls register_ccd() to SHA-256-hash and persist to causal_context_docs
#
# Result: 10 CCDs in causal_context_docs with non-empty <EvidenceNodes>.
#
# Run from project root:
#   Rscript --no-init-file R/run_layer3_statefarm_wc_ccds.R
# ==============================================================================

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(dplyr)
  library(glue)
  library(dagitty)
  library(xml2)
  library(digest)
})

source("R/layer1_ingest_schedule_p.R")
source("R/layer1_chainladder.R")
source("R/layer2_detect_triangle_anomalies.R")
source("R/layer3_build_reserving_dag.R")
source("R/layer3_generate_ccd.R")

DB_PATH    <- "data/database/causal_reserving.db"
MACRO_PATH <- "data/macro/wc_macro_evidence_1998_2007.csv"
LOB        <- "WC"
GRCODE     <- 1767L
GRNAME     <- "State Farm Mut Grp"
AYS        <- 1998L:2007L
# State Farm key causal path nodes (always included in subgraph)
KEY_PATH_NODES <- c("medical_cpi", "avg_case_value",
                    "case_reserve_opening", "development_factor", "ultimate_loss")

cat(glue("=== Layer 3 CCD Pipeline: {GRNAME} WC AY 1998-2007 ===\n\n"))

# ── 1. Load triangle data from DB ─────────────────────────────────────────────
con <- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)

tri_df <- DBI::dbGetQuery(con, glue_sql(
  "SELECT accident_year, development_lag, cumulative_paid_loss, earned_premium
   FROM triangles WHERE lob = {LOB} AND grcode = {GRCODE}
   ORDER BY accident_year, development_lag",
  .con = con
))
cat(glue("Loaded {nrow(tri_df)} triangle rows for {GRNAME} WC\n"))
stopifnot(nrow(tri_df) > 0L)

# ── 2. Run anomaly detection over the full triangle ───────────────────────────
# Add lob column for compute_ata_factors()
tri_for_ata           <- tri_df
tri_for_ata$lob       <- LOB
tri_for_ata$grcode    <- GRCODE
tri_for_ata$cumulative_incurred_loss <- tri_for_ata$cumulative_paid_loss  # proxy

ata_df <- compute_ata_factors(tri_for_ata)
cat(glue("Computed {nrow(ata_df)} ATA factor rows\n"))

zscore_flags <- detect_ata_zscore(ata_df, z_threshold = 2.5)
diag_flags   <- detect_diagonal_effect(tri_for_ata)
anomalies_all <- combine_anomaly_signals(zscore_flags, diag_flags)
cat(glue("Anomaly detection: {nrow(anomalies_all)} flags total ",
         "({sum(anomalies_all$rule_id=='ATA_ZSCORE')} ATA_ZSCORE, ",
         "{sum(anomalies_all$rule_id=='DIAGONAL_EFFECT')} DIAGONAL_EFFECT)\n"))

# Persist anomaly flags (delete old WC grcode=1767 flags first)
DBI::dbExecute(con,
  glue_sql("DELETE FROM anomaly_flags WHERE lob = {LOB}", .con = con))
if (nrow(anomalies_all) > 0L) {
  DBI::dbWriteTable(con, "anomaly_flags", anomalies_all, append = TRUE)
  cat(glue("Persisted {nrow(anomalies_all)} anomaly flags to DB\n"))
}

DBI::dbDisconnect(con)

# ── 3. Chain-ladder: derive development_factor and ultimate_loss per AY ───────
# Use eval_year = 2007 (last full diagonal of the 1998-2007 dataset)
cl_result  <- compute_chainladder_reserve(tri_df, eval_year = 2007L)
cat(glue("\nChain-ladder complete. Total IBNR: ${formatC(sum(cl_result$ibnr), ",
         "format='f', digits=0, big.mark=',')}\n"))
cat(glue("ATA factors: {paste(round(attr(cl_result,'ata_factors'),3), collapse=' | ')}\n\n"))

# ── 4. Load macro evidence CSV ────────────────────────────────────────────────
macro_df <- read.csv(MACRO_PATH, comment.char = "#", stringsAsFactors = FALSE)
cat(glue("Loaded macro CSV: {nrow(macro_df)} rows\n"))

# ── 5. Build average case value proxy per AY ──────────────────────────────────
# avg_case_value proxy: lag-1 paid loss is a mix of frequency × severity.
# We index medical_cpi cumulatively from 1998 base to estimate the severity
# component. avg_case_value (index, 1998=100) = cumulative medical CPI index.
macro_df <- macro_df |>
  dplyr::arrange(accident_year) |>
  dplyr::mutate(
    medical_cpi_index = cumprod(1 + medical_cpi / 100) * 100,
    # avg_case_value: medical index × 250 (rough $250 base per unit in $000s)
    avg_case_value_proxy = round(medical_cpi_index * 2.5, 1)
  )

# ── 6. Build DAG ──────────────────────────────────────────────────────────────
dag <- build_reserving_dag()
cat("DAG loaded.\n")

# ── 7. Loop over accident years and generate CCDs ─────────────────────────────
con <- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)
on.exit(DBI::dbDisconnect(con), add = TRUE)

# Clear old WC CCDs for AYs 1998-2007 so we get clean re-runs
DBI::dbExecute(con,
  "DELETE FROM causal_context_docs WHERE lob = 'WC'
   AND accident_year BETWEEN 1998 AND 2007")
cat("Cleared existing WC 1998-2007 CCDs.\n\n")

results <- vector("list", length(AYS))

for (i in seq_along(AYS)) {
  ay <- AYS[i]
  cat(glue("--- AY {ay} ---\n"))

  # -- Anomaly flags for this AY
  ay_anomalies <- anomalies_all[
    !is.na(anomalies_all$accident_year) &
    anomalies_all$accident_year == ay, ]
  cat(glue("  Anomaly flags: {nrow(ay_anomalies)}\n"))

  # -- Determine flagged DAG nodes from anomaly rules
  flagged_nodes <- character(0L)
  if (any(ay_anomalies$rule_id == "ATA_ZSCORE")) {
    flagged_nodes <- c(flagged_nodes, "case_reserve_opening", "development_factor")
  }
  if (any(ay_anomalies$rule_id == "DIAGONAL_EFFECT")) {
    flagged_nodes <- c(flagged_nodes, "ibnr_emergence")
  }
  # Always include the State Farm key causal path entry points
  flagged_nodes <- union(flagged_nodes, c("medical_cpi", "case_reserve_opening"))
  cat(glue("  Flagged DAG nodes: {paste(flagged_nodes, collapse=', ')}\n"))

  # -- Extract active subgraph
  subgraph <- extract_active_subgraph(dag, flagged_nodes)
  # Ensure every node in the key causal path is present
  subgraph$nodes <- union(subgraph$nodes, KEY_PATH_NODES)
  # Ensure key path edges are present
  key_edges <- data.frame(
    from = c("medical_cpi",       "avg_case_value",
             "case_reserve_opening", "development_factor"),
    to   = c("avg_case_value",    "case_reserve_opening",
             "development_factor",   "ultimate_loss"),
    stringsAsFactors = FALSE
  )
  subgraph$edges <- unique(rbind(subgraph$edges, key_edges))
  cat(glue("  Subgraph: {length(subgraph$nodes)} nodes, ",
           "{nrow(subgraph$edges)} edges\n"))

  # -- Pull chain-ladder values for this AY
  cl_ay <- cl_result[cl_result$accident_year == ay, ]
  stopifnot(nrow(cl_ay) == 1L)

  # case_reserve_opening: lag-1 paid loss for this AY (in $000s)
  lag1_loss <- tri_df$cumulative_paid_loss[
    tri_df$accident_year == ay & tri_df$development_lag == 1L]
  stopifnot(length(lag1_loss) == 1L)

  # -- Pull macro evidence for this AY
  m <- macro_df[macro_df$accident_year == ay, ]
  stopifnot(nrow(m) == 1L)

  # -- Build evidence_nodes list (all nodes on the key causal path + macro)
  evidence_nodes <- list(
    # Layer 1: Exogenous shocks (macro)
    medical_cpi        = round(m$medical_cpi, 2),
    gdp_growth         = round(m$gdp_growth, 2),
    unemployment_rate  = round(m$unemployment_rate, 2),
    payroll_growth     = round(m$payroll_growth, 2),
    tort_reform_index  = round(m$tort_reform_index, 2),
    # Layer 2 / 3: Derived from macro
    avg_case_value     = round(m$avg_case_value_proxy, 1),
    # Layer 4: From triangle (proxy for opening reserve adequacy)
    case_reserve_opening = lag1_loss,
    # Layer 5: From chain-ladder
    development_factor = round(cl_ay$ldf, 4),
    ultimate_loss      = round(cl_ay$ultimate_loss, 0),
    ibnr               = round(cl_ay$ibnr, 0)
  )

  cat(glue("  Evidence nodes: medical_cpi={evidence_nodes$medical_cpi}%, ",
           "gdp_growth={evidence_nodes$gdp_growth}%, ",
           "case_reserve_opening=${evidence_nodes$case_reserve_opening}k, ",
           "dev_factor={evidence_nodes$development_factor}, ",
           "ultimate=${formatC(evidence_nodes$ultimate_loss, format='f', ",
           "digits=0, big.mark=',')}\n"))

  # -- Build do-calculus query string
  do_query_str <- glue(
    "P(ultimate_loss | do(case_reserve_opening = adequately_reserved), ",
    "medical_cpi={evidence_nodes$medical_cpi}, ",
    "gdp_growth={evidence_nodes$gdp_growth}) ",
    "for WC AY{ay} [{GRNAME}]"
  )

  # -- Build CCD XML
  ccd_xml <- build_ccd_xml(
    causal_subgraph = subgraph,
    anomaly_context = ay_anomalies,
    evidence_nodes  = evidence_nodes,
    lob             = LOB,
    accident_year   = as.integer(ay),
    do_query_spec   = do_query_str
  )

  # -- Compute SHA-256 and register
  sha256 <- compute_sha256(ccd_xml)
  DBI::dbExecute(con,
    "INSERT OR IGNORE INTO causal_context_docs (sha256, lob, accident_year, ccd_xml)
     VALUES (?, ?, ?, ?)",
    list(sha256, LOB, as.integer(ay), ccd_xml)
  )

  results[[i]] <- list(ay = ay, sha256 = sha256,
                        n_evidence = length(evidence_nodes),
                        n_subgraph_nodes = length(subgraph$nodes),
                        n_anomaly_flags = nrow(ay_anomalies))
  cat(glue("  Registered CCD sha256={substr(sha256,1,16)}...\n\n"))
}

# ── 8. Summary ────────────────────────────────────────────────────────────────
cat("=== Summary ===\n")
ccd_check <- DBI::dbGetQuery(con,
  "SELECT accident_year, sha256,
          LENGTH(ccd_xml) AS xml_bytes,
          CASE WHEN ccd_xml LIKE '%<Evidence%' THEN 'YES' ELSE 'NO' END AS has_evidence
   FROM causal_context_docs WHERE lob = 'WC' AND accident_year BETWEEN 1998 AND 2007
   ORDER BY accident_year")
print(ccd_check)

cat(glue("\nTotal CCDs registered: {nrow(ccd_check)}\n"))
cat(glue("All have <EvidenceNodes>: {all(ccd_check$has_evidence == 'YES')}\n"))

# Print one sample CCD to verify structure
sample_xml <- DBI::dbGetQuery(con,
  "SELECT ccd_xml FROM causal_context_docs WHERE lob='WC' AND accident_year=2001")$ccd_xml[1]
cat("\n=== Sample CCD (AY 2001) ===\n")
cat(sample_xml)
cat("\n")
