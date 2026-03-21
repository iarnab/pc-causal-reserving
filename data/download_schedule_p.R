# ==============================================================================
# data/download_schedule_p.R
# Download CAS Schedule P public dataset
#
# Downloads raw CAS Schedule P CSV files from the CAS website.
# Primary LOB: OL (GL Occurrence / Other Liability – Occurrence).
#
# Skill reference: inst/skills/schedule_p_data.md
#
# Usage:
#   Rscript data/download_schedule_p.R          # downloads OL (default)
#   Rscript data/download_schedule_p.R WC       # downloads Workers Comp
#   Rscript data/download_schedule_p.R OL WC    # downloads multiple LOBs
# ==============================================================================

source("R/layer_1_data/load_schedule_p_raw.R")

dest_dir <- "data/schedule_p"

# LOBs to download: read from command-line args, default to OL
args <- commandArgs(trailingOnly = TRUE)
lobs <- if (length(args) > 0L) toupper(args) else "OL"

for (lob in lobs) {
  tryCatch(
    download_cas_csv(lob, dest_dir, force = FALSE),
    error = function(e) message("ERROR for LOB ", lob, ": ", conditionMessage(e))
  )
}

cat("\nDownload complete. Files are in:", dest_dir, "\n")
cat("To load into SQLite, run:\n")
cat("  source('R/layer_1_data/load_schedule_p_raw.R')\n")
cat("  load_schedule_p_lob('OL', 'data/schedule_p', 'data/database/reserving.db')\n")
