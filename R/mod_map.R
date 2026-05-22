# =============================================================================
# R/mod_map.R - Leaflet map module
# -----------------------------------------------------------------------------
# Single full-width interactive map of every hourly interpolated fix.
# Cartographic design:
#   - Subdued Positron basemap (figure/ground).
#   - Thematic symbols dominate: alpha-blended circles for tracking points,
#     ringed circles sized by sample-size for breeding colonies.
#   - Legend rendered as a top-right HTML control with the active grouping.
#   - Map fitted to the trans-Saharan migration extent on first render.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(leaflet)
  library(leaflet.extras)
  library(dplyr)
  library(htmltools)
})

map_ui <- function(id) {
  ns <- NS(id)
  div(class = "map-wrap",
      leafletOutput(ns("map"), height = "62vh"),
      div(class = "map-overlay",
          textOutput(ns("hint"), inline = TRUE))
  )
}

map_server <- function(id, filtered, processed) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ----- Initial map - rendered once, then proxy-updated for speed -------
    output$map <- renderLeaflet({
      leaflet(options = leafletOptions(
                  worldCopyJump = FALSE, minZoom = 2, maxZoom = 9,
                  zoomControl = TRUE, preferCanvas = TRUE)) %>%
        addTiles(urlTemplate = BASEMAP_URL,
                 attribution = BASEMAP_ATTR,
                 options = tileOptions(opacity = 0.9)) %>%
        fitBounds(lng1 = MAP_BOUNDS$lng1, lat1 = MAP_BOUNDS$lat1,
                  lng2 = MAP_BOUNDS$lng2, lat2 = MAP_BOUNDS$lat2) %>%
        addScaleBar(position = "bottomleft",
                    options = scaleBarOptions(imperial = FALSE)) %>%
        addLayersControl(
          overlayGroups = c("Tracking points",
                            "Colonies"),
          options = layersControlOptions(collapsed = FALSE,
                                         autoZIndex = TRUE)
        )
    })

    # ----- Tracking points (filter-reactive) --------------------
    observe({
      # 1. Pull the high-resolution hourly data stream
      df <- filtered$hourly()
      gm <- filtered$group_mode()
      proxy <- leafletProxy(ns("map"))
      
      proxy %>% clearGroup("Tracking points") %>%
                removeControl("legend")

      if (is.null(df) || nrow(df) == 0) return()

      # 2. CRITICAL FIX: Ensure longitude and latitude are explicitly numeric 
      # and remove any rows that accidentally contain NA coordinates from interpolation
      df <- df %>% 
        dplyr::filter(!is.na(lon), !is.na(lat)) %>%
        dplyr::mutate(lon = as.numeric(lon), lat = as.numeric(lat))

      if (nrow(df) == 0) return()

      # Shared palette resolver (helpers.R)
      pal <- resolve_palette(df, gm)
      df$col <- pal$col

      # 3. Create a safe, pre-formatted string for the popup to prevent sprintf/POSIXct crashes
      df <- df %>%
        dplyr::mutate(
          popup_time = if_else(is.na(timestamp), 
                               format(date, "%Y-%m-%d"), 
                               format(timestamp, "%Y-%m-%d %H:%M UTC"))
        )

      # Downsample for marker rendering (canvas performance safety limit)
      n_max <- 8000
      df_plot <- if (nrow(df) > n_max) df[sample(nrow(df), n_max), ] else df

      proxy %>% addCircleMarkers(
        data = df_plot,
        lng = ~lon, lat = ~lat,
        radius = ~ifelse(phase == "migration", 3.2, 2.4),
        color = ~col, fillColor = ~col, stroke = FALSE,
        fillOpacity = 0.50,
        group = "Tracking points",
        popup = ~sprintf(
          "<b>%s</b> &middot; %s<br/>Bird: <code>%s</code><br/>%s &middot; %s",
          htmltools::htmlEscape(colony_name),
          htmltools::htmlEscape(country),
          htmltools::htmlEscape(bird_id),
          htmltools::htmlEscape(popup_time), # Safe character format used here
          stage_label(phase)
        )
      )

      # Legend
      legend_html <- render_map_legend(
        pal,
        extra_row = '<div class="legend-row"><span class="legend-swatch legend-ring"></span>Breeding colony (size = n birds)</div>'
      )
      proxy %>% addControl(
        html = legend_html,
        position = "topright",
        layerId  = "legend",
        className = "map-legend-wrap"
      )
    })

    # ----- Colony markers (rendered once, sample-size scaled) -------------
    observe({
      cs <- processed$colonies
      pal <- colorFactor(palette = unname(COUNTRY_COLORS),
                         levels  = names(COUNTRY_COLORS))
      leafletProxy(ns("map")) %>%
        clearGroup("Colonies") %>%
        addCircleMarkers(
          data = cs, lng = ~lon, lat = ~lat,
          radius = ~sqrt(n_birds) * 1.8 + 4,
          weight = 1.6, color = "#222",
          fillColor = ~pal(country), fillOpacity = 0.95,
          group = "Colonies",
          layerId = ~colony_id,
          label = ~sprintf("%s, %s - %d birds",
                           colony_name, country, n_birds),
          labelOptions = labelOptions(textsize = "12px", direction = "auto"),
          popup = ~sprintf(
            "<b>%s</b><br/>%s &middot; %s flyway<br/>n = %d birds",
            htmltools::htmlEscape(colony_name),
            htmltools::htmlEscape(country),
            htmltools::htmlEscape(flyway), n_birds
          )
        )
    })

    # ----- Status banner --------------------------------------------------
    output$hint <- renderText({
      n <- nrow(filtered$hourly())
      sprintf("Showing %s hourly tracking intervals - layer-control top-right toggles migration points.",
              fmt_int(n))
    })

    reactive(input$map_marker_click)
  })
}