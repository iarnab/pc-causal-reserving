# ==============================================================================
# inst/shiny/shiny_app.R
# Shiny Dashboard — P&C Causal Reserving Intelligence
#
# Three-tab layout:
#   Tab 1: Anomaly Overview  — ATA triangle heatmap + anomaly flags table
#   Tab 2: Causal Explorer   — interactive DAG + counterfactual query launcher
#   Tab 3: RLHF Review       — paired narrative viewer + Likert rating interface
#
# Do NOT call library() or shinyApp() here.
# app.R handles all library() calls and shinyApp(ui, server).
#
# Required packages (loaded by app.R):
#   shiny, bslib, visNetwork, plotly, reactable, DBI, RSQLite, dplyr, glue
#
# Functions used from other layers (sourced by app.R):
#   build_reserving_dag()              R/layer_3_causal/build_reserving_dag.R
#   query_do_calculus()                R/layer_3_causal/build_reserving_dag.R
#   get_dag_paths()                    R/layer_3_causal/build_reserving_dag.R
#   get_reserving_dag_nodes()          R/layer_3_causal/build_reserving_dag.R
#   synthesize_reserve_narrative()     R/layer_5_llm/synthesize_reserve_narrative.R
#   collect_rlhf_feedback()            R/layer_5_llm/synthesize_reserve_narrative.R
#   generate_ccd()                     R/layer_4_ccd/generate_ccd.R
#   compute_sha256()                   R/layer_4_ccd/generate_ccd.R
# ==============================================================================


# ── Constants ──────────────────────────────────────────────────────────────────

DB_PATH   <- "data/database/reserving.db"
LOB_CODES <- c("WC" = "Workers Compensation",
               "CMP" = "Commercial Multi-Peril",
               "OL"  = "Other Liability",
               "CA"  = "Commercial Auto",
               "MM"  = "Medical Malpractice")


# ── Pure helpers ───────────────────────────────────────────────────────────────

#' Map anomaly severity to Bootstrap colour class
severity_class <- function(severity) {
  switch(severity,
    "error"   = "danger",
    "warning" = "warning",
    "info"    = "info",
    "secondary"
  )
}

#' Build visNetwork node and edge data.frames from the reserving DAG
build_dag_visnetwork <- function(dag, flagged_nodes = character(0L)) {
  nodes_by_layer <- get_reserving_dag_nodes()
  layer_colours  <- c(
    l1_exogenous = "#1C7293",   # deep blue
    l2_exposure  = "#28A745",   # green
    l3_claim     = "#FD7E14",   # orange
    l4_reserve   = "#DC3545",   # red
    l5_ultimate  = "#6F42C1"    # purple
  )

  node_df <- do.call(rbind, lapply(names(nodes_by_layer), function(layer) {
    ns <- nodes_by_layer[[layer]]
    data.frame(
      id     = ns,
      label  = gsub("_", "\n", ns),
      group  = layer,
      color  = layer_colours[[layer]],
      shadow = ns %in% flagged_nodes,
      font.color = "white",
      stringsAsFactors = FALSE
    )
  }))

  dag_edges  <- dagitty::edges(dag)
  edge_df    <- data.frame(
    from   = dag_edges$v,
    to     = dag_edges$w,
    arrows = "to",
    stringsAsFactors = FALSE
  )

  list(nodes = node_df, edges = edge_df)
}


# ── UI ─────────────────────────────────────────────────────────────────────────

ui <- bslib::page_navbar(
  title = "P&C Causal Reserving",
  theme = bslib::bs_theme(version = 5, bootswatch = "flatly"),
  sidebar = bslib::sidebar(
    width = 220,
    selectInput("lob", "Line of Business",
                choices = LOB_CODES, selected = "WC"),
    sliderInput("ay_range", "Accident Years",
                min = 1988L, max = 1997L, value = c(1988L, 1997L), step = 1L,
                sep = ""),
    numericInput("z_threshold", "Z-score threshold",
                 value = 2.5, min = 1.0, max = 5.0, step = 0.5),
    actionButton("run_analysis", "Run Analysis",
                 class = "btn-primary w-100 mt-2"),
    hr(),
    helpText("Source: CAS Schedule P (1988-1997)")
  ),

  # ── Tab 1: Anomaly Overview ────────────────────────────────────────────────
  bslib::nav_panel(
    title = "Anomaly Overview",
    icon  = shiny::icon("triangle-exclamation"),
    bslib::layout_columns(
      col_widths = 12,
      bslib::card(
        bslib::card_header("ATA Factor Heatmap (Z-scores)"),
        plotly::plotlyOutput("ata_heatmap", height = "320px")
      )
    ),
    bslib::layout_columns(
      col_widths = c(8, 4),
      bslib::card(
        bslib::card_header("Anomaly Flags"),
        reactable::reactableOutput("anomaly_table")
      ),
      bslib::layout_columns(
        col_widths = 12,
        bslib::value_box(
          title = "Total Flags", value = textOutput("n_total_flags"),
          showcase = shiny::icon("flag"), theme = "primary"
        ),
        bslib::value_box(
          title = "Errors", value = textOutput("n_errors"),
          showcase = shiny::icon("circle-xmark"), theme = "danger"
        ),
        bslib::value_box(
          title = "Warnings", value = textOutput("n_warnings"),
          showcase = shiny::icon("triangle-exclamation"), theme = "warning"
        )
      )
    )
  ),

  # ── Tab 2: Causal Explorer ─────────────────────────────────────────────────
  bslib::nav_panel(
    title = "Causal Explorer",
    icon  = shiny::icon("diagram-project"),
    bslib::layout_sidebar(
      sidebar = bslib::sidebar(
        position = "right", width = 300,
        bslib::card(
          bslib::card_header("Node Info"),
          uiOutput("node_info_panel")
        ),
        bslib::card(
          bslib::card_header("Counterfactual Query"),
          selectInput("intervention_node", "Intervene on:",
                      choices = c("tort_reform", "medical_cpi", "gdp_growth",
                                  "unemployment_rate", "payroll_growth")),
          numericInput("intervention_value", "Value (% change):",
                       value = 0, step = 1),
          actionButton("run_counterfactual", "Run Query",
                       class = "btn-outline-primary w-100"),
          hr(),
          verbatimTextOutput("counterfactual_result")
        ),
        bslib::card(
          bslib::card_header("Active Paths"),
          verbatimTextOutput("path_viewer")
        )
      ),
      bslib::card(
        bslib::card_header("Causal DAG — click a node to explore"),
        visNetwork::visNetworkOutput("dag_network", height = "520px")
      )
    )
  ),

  # ── Tab 3: RLHF Review ─────────────────────────────────────────────────────
  bslib::nav_panel(
    title = "RLHF Review",
    icon  = shiny::icon("star-half-stroke"),
    selectInput("review_ay", "Accident Year:",
                choices = 1988:1997, selected = 1993L, width = "200px"),
    bslib::layout_columns(
      col_widths = c(6, 6),
      bslib::card(
        bslib::card_header(
          "Reserve Narrative",
          bslib::card_header_buttons(
            actionButton("regenerate_narrative", "Regenerate",
                         class = "btn-sm btn-outline-secondary")
          )
        ),
        uiOutput("narrative_display"),
        bslib::card_footer(
          tags$small(class = "text-muted",
            "CCD SHA-256: ", textOutput("ccd_sha256_display", inline = TRUE))
        )
      ),
      bslib::card(
        bslib::card_header("Actuary Rating"),
        selectInput("reviewer_id", "Reviewer:",
                    choices = c("actuary_1","actuary_2","actuary_3",
                                "actuary_4","actuary_5","actuary_6")),
        radioButtons("rating_accuracy", "1. Actuarial Accuracy",
                     choices = setNames(1:5, c("1 Inaccurate","2","3 Neutral","4","5 Fully Accurate")),
                     inline = TRUE),
        radioButtons("rating_coherence", "2. Causal Coherence",
                     choices = setNames(1:5, c("1 No logic","2","3","4","5 Clear chain")),
                     inline = TRUE),
        radioButtons("rating_tone", "3. Regulatory Tone",
                     choices = setNames(1:5, c("1 Inappropriate","2","3","4","5 Appropriate")),
                     inline = TRUE),
        radioButtons("rating_completeness", "4. Completeness",
                     choices = setNames(1:5, c("1 Major gaps","2","3","4","5 Complete")),
                     inline = TRUE),
        radioButtons("rating_conciseness", "5. Conciseness",
                     choices = setNames(1:5, c("1 Too verbose","2","3","4","5 Well-calibrated")),
                     inline = TRUE),
        textAreaInput("reviewer_notes", "Notes:", rows = 3),
        actionButton("submit_rating", "Submit Rating",
                     class = "btn-success w-100")
      )
    ),
    bslib::card(
      bslib::card_header("Rating History"),
      reactable::reactableOutput("rating_history_table")
    )
  )
)


# ── Server ─────────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  # -- Reactive: build DAG once ------------------------------------------------
  dag_r <- reactive({ build_reserving_dag() })

  # -- Reactive: load data and run analysis on button click --------------------
  analysis_r <- eventReactive(input$run_analysis, {
    req(file.exists(DB_PATH))
    con <- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    ata_df <- DBI::dbGetQuery(con, glue::glue(
      "SELECT * FROM ata_factors WHERE lob = '{input$lob}'
       AND accident_year BETWEEN {input$ay_range[1]} AND {input$ay_range[2]}"
    ))

    tri_df <- DBI::dbGetQuery(con, glue::glue(
      "SELECT * FROM triangles WHERE lob = '{input$lob}'
       AND accident_year BETWEEN {input$ay_range[1]} AND {input$ay_range[2]}"
    ))

    if (nrow(ata_df) == 0L) return(list(ata_df = ata_df, anomalies = data.frame()))

    zscore_flags <- detect_ata_zscore(ata_df, z_threshold = input$z_threshold)
    diag_flags   <- detect_diagonal_effect(tri_df)
    anomalies    <- combine_anomaly_signals(zscore_flags, diag_flags)

    list(ata_df = ata_df, anomalies = anomalies,
         zscore_flags = zscore_flags, diag_flags = diag_flags)
  })

  # -- Tab 1: Heatmap ----------------------------------------------------------
  output$ata_heatmap <- plotly::renderPlotly({
    res <- analysis_r()
    req(nrow(res$ata_df) > 0L)

    df <- res$ata_df
    # Compute z-scores for heatmap colour
    df <- df |>
      dplyr::group_by(from_lag) |>
      dplyr::mutate(
        col_mean = mean(ata_paid, na.rm = TRUE),
        col_sd   = sd(ata_paid,   na.rm = TRUE),
        z_score  = ifelse(col_sd > 0, (ata_paid - col_mean) / col_sd, 0)
      ) |>
      dplyr::ungroup()

    plotly::plot_ly(
      data = df,
      x    = ~from_lag,
      y    = ~factor(accident_year),
      z    = ~z_score,
      type = "heatmap",
      colorscale = list(c(0,"#28A745"), c(0.5,"#FFF3CD"), c(1,"#DC3545")),
      zmin = -3, zmax = 3,
      text = ~glue::glue("AY {accident_year}, Lag {from_lag}\nATA: {round(ata_paid,3)}\nZ: {round(z_score,2)}"),
      hoverinfo = "text"
    ) |>
      plotly::layout(
        xaxis = list(title = "Development Lag (from)"),
        yaxis = list(title = "Accident Year"),
        margin = list(l = 60, b = 50)
      )
  })

  output$anomaly_table <- reactable::renderReactable({
    res <- analysis_r()
    reactable::reactable(
      res$anomalies,
      filterable = TRUE, sortable = TRUE, striped = TRUE,
      columns = list(
        severity = reactable::colDef(
          cell = function(value) {
            cls <- severity_class(value)
            shiny::tags$span(class = glue::glue("badge bg-{cls}"), value)
          }
        ),
        observed = reactable::colDef(format = reactable::colFormat(digits = 3)),
        expected = reactable::colDef(format = reactable::colFormat(digits = 3))
      )
    )
  })

  output$n_total_flags <- renderText({ nrow(analysis_r()$anomalies) })
  output$n_errors      <- renderText({ sum(analysis_r()$anomalies$severity == "error",   na.rm=TRUE) })
  output$n_warnings    <- renderText({ sum(analysis_r()$anomalies$severity == "warning", na.rm=TRUE) })

  # -- Tab 2: Causal Explorer --------------------------------------------------
  selected_node_r <- reactiveVal(NULL)

  output$dag_network <- visNetwork::renderVisNetwork({
    anomalies <- analysis_r()$anomalies
    flagged   <- unique(c(
      if (any(anomalies$rule_id == "ATA_ZSCORE"))    c("case_reserve_opening","development_factor"),
      if (any(anomalies$rule_id == "DIAGONAL_EFFECT")) "ibnr_emergence"
    ))

    vn <- build_dag_visnetwork(dag_r(), flagged_nodes = flagged)

    visNetwork::visNetwork(vn$nodes, vn$edges) |>
      visNetwork::visEdges(arrows = "to", smooth = list(type = "cubicBezier")) |>
      visNetwork::visOptions(highlightNearest = TRUE, nodesIdSelection = TRUE) |>
      visNetwork::visPhysics(stabilization = TRUE) |>
      visNetwork::visEvents(selectNode = "function(params) {
        Shiny.setInputValue('selected_node', params.nodes[0]);
      }")
  })

  observeEvent(input$selected_node, { selected_node_r(input$selected_node) })

  output$node_info_panel <- renderUI({
    node <- selected_node_r()
    if (is.null(node)) return(helpText("Click a node in the DAG."))
    nodes <- get_reserving_dag_nodes()
    layer <- names(Filter(function(ns) node %in% ns, nodes))
    tagList(
      tags$b(node), tags$br(),
      tags$span(class = "text-muted", "Layer: ", layer %||% "unknown"),
      tags$br(),
      tags$small(glue::glue("Paths to ultimate_loss: ",
        "{nrow(get_dag_paths(dag_r(), node, 'ultimate_loss'))}"))
    )
  })

  output$path_viewer <- renderPrint({
    node <- selected_node_r()
    if (is.null(node)) { cat("Select a node."); return() }
    paths <- get_dag_paths(dag_r(), node, "ultimate_loss")
    if (nrow(paths) == 0L) { cat("No paths found."); return() }
    cat(paths$paths, sep = "\n")
  })

  observeEvent(input$run_counterfactual, {
    result <- query_do_calculus(dag_r(),
                                 input$intervention_node, "ultimate_loss")
    output$counterfactual_result <- renderPrint({
      cat("Identifiable:", result$identifiable, "\n")
      cat("Adjustment set:", paste(result$adjustment_set, collapse=", ") %||% "(none)", "\n")
      cat("Paths:\n")
      if (nrow(result$paths) > 0L) cat(result$paths$paths, sep="\n") else cat("(none)")
    })
  })

  # -- Tab 3: RLHF Review ------------------------------------------------------
  ccd_xml_r    <- reactiveVal(NULL)
  narrative_r  <- reactiveVal(NULL)

  observe({
    req(input$run_analysis)
    res  <- analysis_r()
    lob  <- input$lob
    ay   <- as.integer(input$review_ay)

    if (!file.exists(DB_PATH)) return()

    ccd <- tryCatch(
      generate_ccd(dag_r(), res$anomalies, lob, ay, DB_PATH),
      error = function(e) { warning(conditionMessage(e)); NULL }
    )
    ccd_xml_r(ccd)

    if (!is.null(ccd)) {
      narr <- synthesize_reserve_narrative(ccd, lob, ay, dry_run = TRUE)
      narrative_r(narr)
    }
  })

  observeEvent(input$regenerate_narrative, {
    req(!is.null(ccd_xml_r()))
    narr <- synthesize_reserve_narrative(
      ccd_xml_r(), input$lob, as.integer(input$review_ay), dry_run = FALSE
    )
    narrative_r(narr)
  })

  output$narrative_display <- renderUI({
    narr <- narrative_r()
    if (is.null(narr)) return(helpText("Run Analysis to generate a narrative."))
    bslib::card_body(tags$p(narr))
  })

  output$ccd_sha256_display <- renderText({
    ccd <- ccd_xml_r()
    if (is.null(ccd)) return("(not generated)")
    substr(compute_sha256(ccd), 1L, 16L)
  })

  observeEvent(input$submit_rating, {
    req(!is.null(narrative_r()), !is.null(ccd_xml_r()))

    narrative_id <- glue::glue(
      "{input$lob}_{input$review_ay}_{input$reviewer_id}_{as.integer(Sys.time())}"
    )

    tryCatch({
      collect_rlhf_feedback(
        narrative_id   = narrative_id,
        lob            = input$lob,
        accident_year  = as.integer(input$review_ay),
        ccd_sha256     = compute_sha256(ccd_xml_r()),
        narrative_text = narrative_r(),
        ratings        = list(
          accuracy      = as.integer(input$rating_accuracy),
          coherence     = as.integer(input$rating_coherence),
          tone          = as.integer(input$rating_tone),
          completeness  = as.integer(input$rating_completeness),
          conciseness   = as.integer(input$rating_conciseness)
        ),
        reviewer_id    = input$reviewer_id,
        reviewer_notes = input$reviewer_notes,
        db_path        = DB_PATH
      )
      shiny::showNotification("Rating submitted.", type = "message", duration = 3)
    }, error = function(e) {
      shiny::showNotification(
        glue::glue("Error: {conditionMessage(e)}"), type = "error"
      )
    })
  })

  output$rating_history_table <- reactable::renderReactable({
    input$submit_rating  # invalidate on new submission
    req(file.exists(DB_PATH))
    con <- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    hist_df <- DBI::dbGetQuery(con, glue::glue(
      "SELECT narrative_id, reviewer_id, accident_year,
              rating_accuracy, rating_coherence, rating_tone,
              rating_completeness, rating_conciseness,
              reviewer_notes, created_at
       FROM narrative_registry
       WHERE lob = '{input$lob}'
       ORDER BY created_at DESC LIMIT 50"
    ))
    reactable::reactable(hist_df, sortable = TRUE, striped = TRUE,
                         defaultPageSize = 10)
  })
}

# Helper: null-coalescing operator
`%||%` <- function(x, y) if (!is.null(x) && length(x) > 0L) x else y
