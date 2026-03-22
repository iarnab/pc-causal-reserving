#!/usr/bin/env Rscript
# tools/r_wrappers/query_db.R
# Read-only SQLite query wrapper
#
# Accepts JSON on stdin: {db_path, sql}
# Returns JSON on stdout: {status, rows, columns}

args_json <- readLines(con = "stdin", warn = FALSE) |> paste(collapse = "\n")
args      <- jsonlite::fromJSON(args_json)

db_path <- args$db_path
sql     <- args$sql

# Safety: only allow SELECT statements
if (!grepl("^\\s*SELECT", sql, ignore.case = TRUE)) {
  cat(jsonlite::toJSON(
    list(status = "error", message = "Only SELECT queries are allowed."),
    auto_unbox = TRUE
  ))
  quit(status = 0)
}

tryCatch({
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con))

  df <- DBI::dbGetQuery(con, sql)

  cat(jsonlite::toJSON(list(
    status  = "success",
    rows    = nrow(df),
    columns = names(df),
    data    = df
  ), auto_unbox = TRUE))
}, error = function(e) {
  cat(jsonlite::toJSON(list(status = "error", message = conditionMessage(e)),
                       auto_unbox = TRUE))
})
