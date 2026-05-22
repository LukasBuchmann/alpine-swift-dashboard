# =============================================================================
# R/mod_phenology.R - Phenology / latitude-over-time plot
# -----------------------------------------------------------------------------
# Two phenology plots, full-width:
#   1) Latitude as a function of day-of-year, coloured by group.
#   2) Box+jitter of length-of-stay at breeding sites vs. latitude
#      (reproducing the headline finding of Meier et al. 2020).
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
    fluidRow(
      column(7,
        h6("Latitude across the annual cycle", class = "panel-subheading"),
        plotlyOutput(ns("lat_doy"), height = "330px"),
        p(class = "small text-muted mt-1",
          "Each thin line is one bird-year. Steep descents = autumn ",
          "migration; ascents = spring return. ")
      ),
      column(5,
        h6("Breeding-site stay vs. latitude", class = "panel-subheading"),
        plotlyOutput(ns("stay_vs_lat"), height = "330px"),
        p(class = "small text-muted mt-1",
          "Reproduces Meier et al. 2020: birds at higher latitudes occupy ",
          "the breeding site for fewer days.")
      )
    )
  )
}

phenology_server <- function(id, filtered, processed) {
  moduleServer(id, function(input, output, session) {

    # Helper: build qualitative palette for the active grouping
    build_palette <- function(df, gm) {
      lvls <- switch(gm,
                     country = sort(unique(df$country)),
                     colony  = sort(unique(df$colony_name)),
                     flyway  = c("western", "eastern"),
                     year    = sort(unique(as.character(df$year))))
      cols <- switch(gm,
                     country = unname(COUNTRY_COLORS[lvls]),
                     colony  = grDevices::colorRampPalette(
                       suppressWarnings(RColorBrewer::brewer.pal(8, "Set2")))(length(lvls)),
                     flyway  = unname(FLYWAY_COLORS[lvls]),
                     year    = unname(YEAR_COLORS[lvls]))
      setNames(cols, lvls)
    }

    output$lat_doy <- renderPlotly({ suppressWarnings({
      df <- filtered$daily()
      
      shiny::validate(need(nrow(df) > 0,
                    "No data for current filter selection."))

      # Sort data chronologically to ensure accurate gap calculation
      df <- df[order(df$bird_id, df$year, df$date), ]

      # Identify gaps and create distinct line segments
      df <- df %>%
        dplyr::group_by(bird_id, year) %>%
        dplyr::mutate(
          days_diff = as.numeric(difftime(date, dplyr::lag(date), units = "days")),
          new_segment = ifelse(is.na(days_diff) | days_diff > 14, 1, 0),
          segment_id = cumsum(new_segment)
        ) %>%
        dplyr::ungroup() %>%
        dplyr::mutate(line_group = paste(bird_id, year, segment_id))

      if (nrow(df) > 8000) df <- df[sample(nrow(df), 8000), ]

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
        geom_line(alpha = 0.20, linewidth = 0.32) +
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
        # ENABLED MODE BAR AND SCROLL ZOOM HERE
        plotly::config(displayModeBar = TRUE, scrollZoom = TRUE) %>%
        plotly::layout(legend = list(orientation = "h", y = -0.18,
                                     x = 0.5, xanchor = "center"))
    }) })

    output$stay_vs_lat <- renderPlotly({ suppressWarnings({
      df <- filtered$phenology()
      
      shiny::validate(need(nrow(df) > 0, "No phenology data for current selection."))

      ref <- processed$colonies |>
        dplyr::transmute(colony_id, country, breeding_lat = lat)
      
      df_joined <- df %>%
        dplyr::inner_join(ref, by = c("colony_id", "country"))
        
      df2 <- df_joined %>%
        dplyr::mutate(
          w_arr = as.Date(wintering_arrival),
          w_dep = as.Date(wintering_departure),
          
          # FIX THE TIME TRAVEL: If departure is "before" arrival, push it to the next year
          w_dep_corrected = dplyr::if_else(w_dep < w_arr, w_dep + lubridate::years(1), w_dep),
          
          # Use the corrected departure date for the math
          wintering_days = as.numeric(difftime(w_dep_corrected, w_arr, units = "days")),
          total_year_days = ifelse(lubridate::leap_year(year), 366, 365),
          calculated_stay = total_year_days - wintering_days - autumn_mig_days - spring_mig_days
        )
      
      # Filter out NAs and extreme outliers
      df2 <- df2 %>%
        dplyr::filter(!is.na(calculated_stay),
                      calculated_stay > 30, 
                      calculated_stay < 250)

      shiny::validate(need(nrow(df2) > 0,
                    "No valid calculated breeding-stay data for current selection."))

      p <- ggplot(df2, aes(x = breeding_lat, y = calculated_stay,
                           color = country,
                           text = sprintf("%s | %s\nCalculated: %d days at %.1f°N\n(Winter: %d d | Mig: %d d)",
                                          bird_id, country,
                                          as.integer(calculated_stay), breeding_lat,
                                          as.integer(wintering_days),
                                          as.integer(autumn_mig_days + spring_mig_days)))) +
        geom_smooth(aes(group = 1), method = "lm", se = TRUE,
                    color = "#333", fill = "#aaa", linewidth = 0.4, alpha = 0.18) +
        geom_jitter(width = 0.20, height = 0, alpha = 0.65, size = 1.9) +
        scale_color_manual(values = COUNTRY_COLORS, name = NULL) +
        scale_x_continuous(breaks = seq(36, 48, 2),
                           labels = function(b) paste0(b, "°N")) +
        labs(x = "Breeding-site latitude", y = "Days at breeding site (Calculated)") +
        theme_minimal(base_size = 11) +
        theme(legend.position = "bottom",
              panel.grid.minor = element_blank())

      suppressWarnings(
        ggplotly(p, tooltip = "text") %>%
          # ENABLED MODE BAR AND SCROLL ZOOM HERE
          plotly::config(displayModeBar = TRUE, scrollZoom = TRUE) %>%
          plotly::layout(legend = list(orientation = "h", y = -0.18,
                                       x = 0.5, xanchor = "center"))
      )
    }) })
  })
}