# =============================================================================
# R/mod_filters.R - Filter sidebar module
# =============================================================================
suppressPackageStartupMessages({
  library(shiny)
  library(shinyWidgets)
  library(readr)
  library(dplyr)
})

.colonies_static <- tryCatch(
  readr::read_csv(file.path("data", "raw", "colonies.csv"), show_col_types = FALSE) |> dplyr::arrange(country, colony_name),
  error = function(e) data.frame(colony_name = character(0), country = character(0), flyway = character(0))
)

.choices_grouped <- if (nrow(.colonies_static) > 0) split(.colonies_static$colony_name, .colonies_static$country) else list()
.all_colonies     = unname(unlist(.choices_grouped))
.western_colonies <- .colonies_static$colony_name[.colonies_static$flyway == "western"]
.eastern_colonies <- .colonies_static$colony_name[.colonies_static$flyway == "eastern"]

filters_ui <- function(id) {
  ns <- NS(id)
  tagList(
    h5("Filters", class = "filter-heading"),
    div(class = "quick-filters",
        actionButton(ns("qf_all"), "All", class = "qf-btn"),
        actionButton(ns("qf_western"), "W flyway", class = "qf-btn"),
        actionButton(ns("qf_eastern"), "E flyway", class = "qf-btn"),
        actionButton(ns("qf_clear"), "Clear", class = "qf-btn")
    ),
    pickerInput(ns("country"), label = NULL, choices = .choices_grouped, selected = .all_colonies, multiple = TRUE, options = pickerOptions(actionsBox = TRUE, liveSearch = TRUE, size = 11, selectedTextFormat = "count > 3", countSelectedText = "{0} colonies selected")),
    sliderTextInput(ns("year"), "Year",
                    choices = c("2014", "2015", "2016", "2017"),
                    selected = c("2014", "2017"), grid = TRUE),
    radioButtons(ns("group_mode"), "Color by", choices = c("Country" = "country", "Colony" = "colony", "Flyway" = "flyway", "Year" = "year"), selected = "country", inline = TRUE),
    p(class = "small text-muted mt-2", "Tip: use the W/E flyway buttons to compare populations.")
  )
}

filters_server <- function(id, processed) {
  moduleServer(id, function(input, output, session) {
    observeEvent(input$qf_all, { updatePickerInput(session, "country", selected = .all_colonies) })
    observeEvent(input$qf_western, { updatePickerInput(session, "country", selected = .western_colonies) })
    observeEvent(input$qf_eastern, { updatePickerInput(session, "country", selected = .eastern_colonies) })
    observeEvent(input$qf_clear, { updatePickerInput(session, "country", selected = character(0)) })

    sel_years <- reactive({
      yrs <- as.integer(input$year)
      if (length(yrs) == 2) seq(min(yrs), max(yrs)) else yrs
    })

    scope_data <- reactive({
      req(processed$daily)
      df <- processed$daily
      sel <- input$country
      if (is.null(sel) || length(sel) == 0) return(df[0, , drop = FALSE])
      df |> dplyr::filter(colony_name %in% sel, year %in% sel_years())
    })

    # The phenology reactive filter
    filtered_phenology <- reactive({
      req(processed$phenology)
      sel <- input$country
      if (is.null(sel) || length(sel) == 0) {
        return(processed$phenology[0, , drop = FALSE])
      }
      keep_ids <- processed$daily |>
        dplyr::filter(colony_name %in% sel) |>
        dplyr::pull(colony_id) |> unique()
      processed$phenology |>
        dplyr::filter(colony_id %in% keep_ids, year %in% sel_years())
    })

    list(
      daily      = scope_data,
      phenology  = filtered_phenology,
      years      = sel_years,
      group_mode = reactive(input$group_mode)
    )
  })
}