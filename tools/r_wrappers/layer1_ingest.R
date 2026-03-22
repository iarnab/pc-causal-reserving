#!/usr/bin/env Rscript
# tools/r_wrappers/layer1_ingest.R
# R wrapper for Layer 1: Data Ingestion
#
# Accepts JSON on stdin: {file_path, db_path, lob}
# Returns JSON on stdout: {status, rows_ingested, lobs, companies, warnings}

args_json <- readLines(con = "stdin", warn = FALSE) |> paste(collapse = "\n")
args      <- jsonlite::fromJSON(args_json)

db_path   <- args$db_path
file_path <- args[["file_path"]]
lob       <- args[["lob"]]     # may be NULL

tryCatch({
  source(here::here("R/layer1_ingest_schedule_p.R"))
  source(here::here("R/layer1_load_schedule_p_raw.R"))

  result <- ingest_schedule_p(
    file_path = file_path,
    db_path   = db_path,
    lob       = lob
  )

  cat(jsonlite::toJSON(c(list(status = "success"), result), auto_unbox = TRUE))
}, error = function(e) {
  cat(jsonlite::toJSON(list(status = "error", message = conditionMessage(e)),
                       auto_unbox = TRUE))
})
