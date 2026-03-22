#!/usr/bin/env Rscript
# tools/r_wrappers/layer3_causal.R
# R wrapper for Layer 3: Causal Reasoning + CCD Generation
#
# Accepts JSON on stdin: {db_path, lob}
# Returns JSON on stdout: {status, ccds_generated, anomalies_traced, sha256_hashes}

args_json <- readLines(con = "stdin", warn = FALSE) |> paste(collapse = "\n")
args      <- jsonlite::fromJSON(args_json)

db_path <- args$db_path
lob     <- args[["lob"]]

tryCatch({
  source(here::here("R/layer_3_causal/build_reserving_dag.R"))
  source(here::here("R/layer_3_causal/generate_ccd.R"))

  result <- run_causal_pipeline(
    db_path = db_path,
    lob     = lob
  )

  cat(jsonlite::toJSON(c(list(status = "success"), result), auto_unbox = TRUE))
}, error = function(e) {
  cat(jsonlite::toJSON(list(status = "error", message = conditionMessage(e)),
                       auto_unbox = TRUE))
})
