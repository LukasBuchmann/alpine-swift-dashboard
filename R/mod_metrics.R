# =============================================================================
# R/mod_metrics.R - Summary KPI value boxes (top of dashboard)
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(dplyr)
})

metrics_ui <- function(id) {
  ns <- NS(id)
  layout_columns(
    fill = FALSE, col_widths = c(4, 4, 4),
    value_box(title = "Individuals tracked",
              value = textOutput(ns("n_birds")),
              showcase = bsicons::bs_icon("binoculars"),
              theme  = "success"),
    value_box(title = "Daily fixes",
              value = textOutput(ns("n_fixes")),
              showcase = bsicons::bs_icon("geo-alt"),
              theme  = "primary"),
    value_box(title = "Populations / colonies",
              value = textOutput(ns("n_pops")),
              showcase = bsicons::bs_icon("diagram-3"),
              theme  = "success")
  )
}

metrics_server <- function(id, filtered) {
  moduleServer(id, function(input, output, session) {
    output$n_birds <- renderText({
      fmt_int(length(unique(filtered$daily()$bird_id)))
    })
    output$n_fixes <- renderText({
      fmt_int(nrow(filtered$daily()))
    })
    output$n_pops <- renderText({
      n_country <- length(unique(filtered$daily()$country))
      n_colony  <- length(unique(filtered$daily()$colony_id))
      sprintf("%d / %d", n_country, n_colony)
    })
  })
}
