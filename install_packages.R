# Install all R dependencies for the P&C Causal Reserving project
# Run once after cloning: Rscript install_packages.R

options(repos = c(CRAN = "https://cloud.r-project.org"))

# Causal Inference
install.packages("dagitty")
install.packages("bnlearn")   # Phase 2: Bayesian structure learning

# Anomaly Detection
install.packages("anomalize")

# Data I/O
install.packages("DBI")
install.packages("RSQLite")
install.packages("openxlsx")  # Schedule P Excel ingestion

# Data Wrangling
install.packages("dplyr")
install.packages("tidyr")
install.packages("purrr")
install.packages("stringr")
install.packages("readr")

# API Integration
install.packages("httr2")
install.packages("jsonlite")

# XML / CCD Construction
install.packages("xml2")

# Cryptography / Audit
install.packages("digest")

# Visualisation
install.packages("ggplot2")
install.packages("plotly")
install.packages("visNetwork")

# Shiny Dashboard
install.packages("shiny")
install.packages("bslib")
install.packages("reactable")

# Reporting
install.packages("officer")
install.packages("flextable")
install.packages("knitr")
install.packages("rmarkdown")

# Testing
install.packages("testthat")
install.packages("assertthat")

# Utility
install.packages("here")
install.packages("glue")
install.packages("fs")

cat("All packages installed successfully!\n")
