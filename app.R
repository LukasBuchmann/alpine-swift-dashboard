# =============================================================================
# app.R - Alpine Swift Dashboard
# =============================================================================
# Single-page layout (after Slocum et al. on integrated multi-modal
# geovisualization): the dashboard's only map combines the static and
# animated views. Press Play to see migration; press Reset to return to
# the static overview.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(bsicons)
})

# Silence the well-known plotly/jsonlite deprecation noise about named
# vectors. Harmless future-deprecation warning that floods the console.
tryCatch(
  globalCallingHandlers(warning = function(w) {
    msg <- conditionMessage(w)
    if (grepl("keep_vec_names|Input to asJSON", msg, ignore.case = TRUE)) {
      invokeRestart("muffleWarning")
    }
  }),
  error = function(e) invisible(NULL)
)

source("R/helpers.R",          local = TRUE)
source("R/data_acquisition.R", local = TRUE)
source("R/data_processing.R",  local = TRUE)
source("R/mod_filters.R",      local = TRUE)
source("R/mod_phenology.R",    local = TRUE)
source("R/mod_metrics.R",      local = TRUE)
source("R/mod_animation.R",    local = TRUE)

# --- Theme -------------------------------------------------------------------
swift_theme <- bs_theme(
  version    = 5,
  bootswatch = "flatly",
  primary    = "#1B5E20",
  "navbar-bg"  = "#1B5E20",
  "navbar-fg"  = "#FFFFFF",
  base_font  = font_google("Inter"),
  heading_font = font_google("Inter")
)

# =============================================================================
# UI
# =============================================================================
ui <- page_navbar(
  title = span(
    span("Alpine Swift Migration"),
    span(class = "navbar-subtitle",
         "trans-Saharan tracking, 4 populations, 2014-2016")
  ),
  theme = swift_theme,
  fillable = FALSE,
  header = tagList(
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "custom.css"),
      tags$meta(name = "viewport",
                content = "width=device-width, initial-scale=1.0"),
      # ---- First-load overlay: visible until Shiny finishes initial work ----
      tags$script(HTML(
        "$(document).on('shiny:idle', function() {",
        "  var el = document.getElementById('init-loader');",
        "  if (el) { el.classList.add('fade-out');",
        "            setTimeout(function(){ el.remove(); }, 600); }",
        "});"))
    ),
    tags$div(id = "init-loader", class = "init-loader",
             tags$div(class = "init-loader-spinner"),
             tags$div(class = "init-loader-text",
                      "Loading Alpine Swift tracks…"))
  ),

  # ---- Sidebar (global filters) ----
  sidebar = sidebar(
    width = 290,
    open = "always",
    filters_ui("filters"),
    hr(),
    div(class = "small data-source-block",
        uiOutput("data_source_banner")),
    hr(),
    div(class = "small text-muted",
        HTML(paste0(
          "Built for CCES (ZHAW). Reference: Meier et al. 2020, ",
          "<a href='https://doi.org/10.1111/jav.02515' target='_blank'>",
          "doi:10.1111/jav.02515</a>.")))
  ),

  # ---- Main panel: KPIs + merged map + phenology context plots ----
  nav_panel(
    title = "Dashboard",
    icon  = bsicons::bs_icon("globe-europe-africa"),
    metrics_ui("metrics"),
    card(
      card_header(
        div(class = "d-flex justify-content-between align-items-center",
            span("Trans-Saharan migration - static + animated map",
                 class = "panel-heading"),
            span(class = "card-tools small text-muted",
                 "Toggle layers top-right; press Play to animate"))
      ),
      animation_ui("anim")
    ),
    card(
      card_header(span("Linked phenology plots", class = "panel-heading")),
      phenology_ui("pheno")
    )
  ),

  nav_panel(
    title = "About",
    icon  = bsicons::bs_icon("info-circle"),
    div(class = "about-wrap",
        card(
          card_header(span("About this dashboard",
                           class = "panel-heading")),
          card_body(includeMarkdown("reports/about.md"))
        )
    )
  ),

  footer = div(class = "app-footer",
               span("Alpine Swift Migration Dashboard"),
               span(" - CCES FS 2026 - ZHAW Environmental Science"))
)

# =============================================================================
# Server
# =============================================================================
server <- function(input, output, session) {

  withProgress(message = "Loading tracking data", value = 0.1, {
    incProgress(0.4)
    processed <- load_processed()
    incProgress(0.9)
  })

  filtered <- filters_server("filters", processed)
  metrics_server("metrics", filtered)
  phenology_server("pheno", filtered, processed)
  animation_server("anim", filtered, processed)

  output$data_source_banner <- renderUI({
    src <- if (is.null(processed$source)) "unknown" else processed$source
    n_col <- length(unique(processed$colony_summary$colony_id))
    n_bird <- sum(processed$colony_summary$n_birds)
    if (identical(src, "movebank-local")) {
      div(class = "data-source data-source-real",
          span(class = "src-dot src-dot-green"),
          tags$b("Real Movebank Data Repository"), br(),
          span(class = "text-muted small",
               sprintf("%d colonies, %d birds", n_col, n_bird)))
    } else {
      div(class = "data-source data-source-synth",
          span(class = "src-dot src-dot-amber"),
          tags$b("Synthetic (Meier 2020 calibrated)"), br(),
          span(class = "text-muted small",
               "Drop Movebank CSVs in data/raw/movebank/ to use real data."))
    }
  })
}

shinyApp(ui, server)
