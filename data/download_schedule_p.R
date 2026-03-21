# ==============================================================================
# data/download_schedule_p.R
# Download CAS Schedule P public dataset
#
# Downloads the CAS Research Working Party Schedule P dataset (1988-1997).
# Workers Compensation (WC) is the primary demo LOB.
#
# Usage: Rscript data/download_schedule_p.R
# ==============================================================================

options(timeout = 300)

dest_dir <- "data/schedule_p"
if (!dir.exists(dest_dir)) dir.create(dest_dir, recursive = TRUE)

# CAS Schedule P data is available from the CAS website
# Visit: https://www.casact.org/publications-research/research/research-resources/loss-reserving-data-pulled-naic-schedule-p
# Download the CSV files manually and place them in data/schedule_p/
# with the following naming convention: <LOB>_schedule_p.csv

cat("Schedule P data must be downloaded manually from the CAS website.\n")
cat("URL: https://www.casact.org/publications-research/research/research-resources/loss-reserving-data-pulled-naic-schedule-p\n")
cat("Place CSV files in: data/schedule_p/\n")
cat("Required format: lob, accident_year, development_lag, cumulative_paid_loss,\n")
cat("                 cumulative_incurred_loss, earned_premium\n")
