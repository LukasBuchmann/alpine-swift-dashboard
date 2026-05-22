# =============================================================================
# R/mod_phenology.R - Phenology plot (single panel)
# -----------------------------------------------------------------------------
# Latitude as a function of day-of-year, coloured by group, with line breaks
# at tracking gaps >14 days.
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
    p(class = "small text-muted mt-1",
      "Each thin line is one bird-year track segment. Steep descents = ",
      "autumn migration; ascents = spring return. Dashed line marks the ",
      "Tropic of Cancer; all populations winter below it. Tracking gaps ",
      "longer than 14 days break the line.")
  )
}

phenology_server <- function(id, filtered, processed) {
  moduleServer(id, function(input, output, session) {

    build_palette <- function(df, gm) {
      lvls <- switch(gm,
                     country = sort(unique(df$country)),
                     colony  = sort(unique(df$colony_name)),
                     flyway  = c("western", "eastern"),
                     year    = sort(unique(as.character(df$year))))
      cols <- switch(gm,
                     country = unname(COUNTRY_COLORS[lvls]),
                     colony  = grDevices::colorRampPalette(
                       suppressWarnings(RColorBrewer::brewer.pal(8, "Dark2"))
                     )(length(lvls)),
                     flyway  = unname(FLYWAY_COLORS[lvls]),
                     year    = unname(YEAR_COLORS[lvls]))
      setNames(cols, lvls)
    }

    output$lat_doy <- renderPlotly({ suppressWarnings({
      df <- filtered$daily()
      shiny::validate(need(nrow(df) > 0,
                    "No data for current filter selection."))

      df <- df[order(df$bird_id, df$year, df$date), ]
      df <- df %>%
        dplyr::group_by(bird_id, year) %>%
        dplyr::mutate(
          days_diff   = as.numeric(difftime(date, dplyr::lag(date),
                                            units = "days")),
          new_segment = ifelse(is.na(days_diff) | days_diff > 14, 1, 0),
          segment_id  = cumsum(new_segment)
        ) %>%
        dplyr::ungroup() %>%
        dplyr::mutate(line_group = paste(bird_id, year, segment_id))

      # Deterministic sample so Color by changes don't shuffle the lines
      if (nrow(df) > 8000) {
        set.seed(2026L)
        df <- df[sample(nrow(df), 8000), ]
      }

      gm <- filtered$group_mode()
      df$group_col <- switch(gm,
                             country = df$country,
                             colony  = df$colony_name,
                             flyway  = df$flyway,
                             year    = as.character(df$year))
      pal <- build_palette(df, gm)

      p <- ggplot(df, aes(x = doy, y = lat,
                          color = group_col,
                          group = line_group,
                          text = sprintf("%s | %s\n%s | lat %.1f",
                                         bird_id, group_col,
                                         format(date, "%d %b %Y"), lat))) +
        geom_line(alpha = 0.22, linewidth = 0.32) +
        geom_hline(yintercept = 23.4366, linetype = "dashed",
                   color = "#888", linewidth = 0.35) +
        scale_color_manual(values = pal, name = NULL) +
        scale_x_continuous(
          breaks = c(1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335),
          labels = c("Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"),
          minor_breaks = NULL,
          expand = expansion(mult = c(0.005, 0.005))) +
        scale_y_continuous(breaks = seq(-10, 60, 10),
                           limits = c(-15, 60),
                           oob = scales::squish) +
        labs(x = NULL, y = "Latitude (°N)") +
        theme_minimal(base_size = 11) +
        theme(legend.position = "bottom",
              panel.grid.minor = element_blank(),
              axis.text.x = element_text(size = 9))

      ggplotly(p, tooltip = "text") %>%
        plotly::config(displayModeBar = TRUE, scrollZoom = TRUE) %>%
        plotly::layout(legend = list(orientation = "h", y = -0.18,
                                     x = 0.5, xanchor = "center"))
    }) })
  })
}
