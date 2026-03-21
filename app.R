# ==============================================================================
# app.R
# Shiny Application Entry Point
#
# Loads all dependencies, sources all layer scripts, and launches the
# three-tab Shiny dashboard. Run with: shiny::runApp("app.R")
# ==============================================================================

library(shiny)
library(bslib)
library(visNetwork)
library(plotly)
library(reactable)
library(DBI)
library(RSQLite)
library(dplyr)
library(glue)
library(dagitty)
library(xml2)
library(digest)
library(httr2)
library(jsonlite)
library(anomalize)

# Source all layer scripts
source("R/layer_1_data/ingest_schedule_p.R")
source("R/layer_2_anomaly/detect_triangle_anomalies.R")
source("R/layer_3_causal/build_reserving_dag.R")
source("R/layer_4_ccd/generate_ccd.R")
source("R/layer_5_llm/claude_client.R")
source("R/layer_5_llm/synthesize_reserve_narrative.R")

# Source the Shiny UI and server
source("inst/shiny/shiny_app.R")

shinyApp(ui = ui, server = server)
