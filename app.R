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

# Source all layer scripts
source("R/layer1_ingest_schedule_p.R")
source("R/layer1_load_schedule_p_raw.R")
source("R/layer1_chainladder.R")
source("R/layer2_detect_triangle_anomalies.R")
source("R/layer3_build_reserving_dag.R")
source("R/layer3_generate_ccd.R")
source("R/layer4_claude_client.R")
source("R/layer4_synthesize_reserve_narrative.R")

# Source the Shiny UI and server
source("inst/shiny/shiny_app.R")

shinyApp(ui = ui, server = server)
