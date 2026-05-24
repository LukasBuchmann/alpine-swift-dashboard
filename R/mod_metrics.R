# =============================================================================
# R/mod_metrics.R - Summary KPI strip (lives in the navbar, top-right)
# =============================================================================
suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
})

metrics_ui <- function(id) {
  ns <- NS(id)
  div(class = "navbar-metrics",
      div(class = "navbar-metric",
          span(class = "navbar-metric-value",
               textOutput(ns("n_birds"), inline = TRUE)),
          span(class = "navbar-metric-label", "Individuals tracked")),
      div(class = "navbar-metric",
          span(class = "navbar-metric-value",
               textOutput(ns("n_fixes"), inline = TRUE)),
          span(class = "navbar-metric-label", "Daily fixes")),
      div(class = "navbar-metric",
          span(class = "navbar-metric-value",
               textOutput(ns("n_pops"), inline = TRUE)),
          span(class = "navbar-metric-label", "Populations / colonies"))
  )
}

metrics_server <- function(id, filtered) {
  moduleServer(id, function(input, output, session) {
    output$n_birds <- renderText({
      format(length(unique(filtered$daily()$bird_id)), big.mark = " ")
    })
    output$n_fixes <- renderText({
      format(nrow(filtered$daily()), big.mark = " ")
    })
    output$n_pops <- renderText({
      sprintf("%d / %d",
              length(unique(filtered$daily()$country)),
              length(unique(filtered$daily()$colony_id)))
    })
  })
}
