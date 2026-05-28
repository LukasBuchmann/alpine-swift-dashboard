# =============================================================================
# R/mod_phenology.R - Phenology / latitude-over-time plot
# -----------------------------------------------------------------------------
# Full-width latitude over the annual cycle.  Each thin coloured line is one
# bird-year track; steep descents = autumn migration, ascents = spring return.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(plotly)
  library(dplyr)
  library(ggplot2)
})

phenology_ui <- function(id) {
  ns <- NS(id)
  tagList(
    h6("Latitude across the annual cycle", class = "panel-subheading"),
    plotlyOutput(ns("lat_doy"), height = "360px"),
div(class = "plot-caption",
    paste0(
      "Latitude (degrees N) across the annual cycle. Each thin ",
      "line is one bird-year. Steep descents = autumn migration; ",
      "ascents = spring return. Lines are split where the tracker ",
      "had no fix for more than 14 days, so no fake interpolation ",
      "is drawn across gaps."
    )
    )
  )
}

phenology_server <- function(id, filtered, processed) {
  moduleServer(id, function(input, output, session) {

    output$lat_doy <- renderPlotly({ suppressWarnings({
      df <- filtered$daily()
      shiny::validate(need(nrow(df) > 0, "No data for current filter selection."))

      gm <- filtered$group_mode()
      pal <- resolve_palette(df, gm)
      df$group_col <- switch(gm,
                             country = df$country,
                             colony  = df$colony_name,
                             flyway  = df$flyway,
                             year    = as.character(df$year))

      df <- df[order(df$bird_id, df$year, df$date), ]
      df <- df %>%
        dplyr::group_by(bird_id, year) %>%
        dplyr::mutate(
          days_diff   = as.numeric(difftime(date, dplyr::lag(date), units = "days")),
          new_segment = ifelse(is.na(days_diff) | days_diff > 14, 1, 0),
          segment_id  = cumsum(new_segment)
        ) %>%
        dplyr::ungroup() %>%
        dplyr::mutate(line_group = paste(bird_id, year, segment_id))

      p <- ggplot(df, aes(x = doy, y = lat, color = group_col,
                          group = line_group,
                          text = sprintf("%s | %s\n%s",
                                         bird_id, group_col,
                                         format(date, "%d %b %Y")))) +
        geom_line(alpha = 0.22, linewidth = 0.5) +
        scale_color_manual(values = pal$colors, name = NULL) +
        scale_x_continuous(
          breaks = c(1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335),
          labels = c("Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"),
          expand = expansion(mult = c(0.005, 0.005))) +
        labs(x = NULL, y = "Latitude (degrees N)") +
        theme_minimal(base_size = 11) +
        theme(legend.position = "bottom",
              panel.grid.minor = element_blank())

      ggplotly(p, tooltip = "text") %>%
        plotly::config(displayModeBar = TRUE, scrollZoom = TRUE) %>%
        plotly::layout(legend = list(orientation = "h", y = -0.18,
                                     x = 0.5, xanchor = "center"))
    }) })
  })
}
