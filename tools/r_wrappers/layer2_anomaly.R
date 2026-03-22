#!/usr/bin/env Rscript
# tools/r_wrappers/layer2_anomaly.R
# R wrapper for Layer 2: Anomaly Detection
#
# Accepts JSON on stdin: {db_path, lob, z_threshold}
# Returns JSON on stdout: {status, flags_written, error_count, warning_count, lobs_scanned}

args_json <- readLines(con = "stdin", warn = FALSE) |> paste(collapse = "\n")
args      <- jsonlite::fromJSON(args_json)

db_path     <- args$db_path
lob         <- args[["lob"]]
z_threshold <- args[["z_threshold"]] %||% 3.0

`%||%` <- function(x, y) if (is.null(x)) y else x

tryCatch({
  source(here::here("R/layer_2_anomaly/detect_triangle_anomalies.R"))

  result <- detect_all_anomalies(
    db_path     = db_path,
    lob         = lob,
    z_threshold = z_threshold
  )

  cat(jsonlite::toJSON(c(list(status = "success"), result), auto_unbox = TRUE))
}, error = function(e) {
  cat(jsonlite::toJSON(list(status = "error", message = conditionMessage(e)),
                       auto_unbox = TRUE))
})
