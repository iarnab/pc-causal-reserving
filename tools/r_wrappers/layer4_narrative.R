#!/usr/bin/env Rscript
# tools/r_wrappers/layer4_narrative.R
# R wrapper for Layer 4: Narrative Generation
#
# Accepts JSON on stdin: {db_path, lob, max_narratives}
# Returns JSON on stdout: {status, narratives_generated, pending_approval, model_used, tokens_used}

args_json <- readLines(con = "stdin", warn = FALSE) |> paste(collapse = "\n")
args      <- jsonlite::fromJSON(args_json)

`%||%` <- function(x, y) if (is.null(x)) y else x

db_path        <- args$db_path
lob            <- args[["lob"]]
max_narratives <- args[["max_narratives"]] %||% 5L

tryCatch({
  source(here::here("R/layer_4_ai/claude_client.R"))
  source(here::here("R/layer_4_ai/synthesize_reserve_narrative.R"))

  result <- synthesize_reserve_narrative(
    db_path        = db_path,
    lob            = lob,
    max_narratives = as.integer(max_narratives)
  )

  cat(jsonlite::toJSON(c(list(status = "success"), result), auto_unbox = TRUE))
}, error = function(e) {
  cat(jsonlite::toJSON(list(status = "error", message = conditionMessage(e)),
                       auto_unbox = TRUE))
})
