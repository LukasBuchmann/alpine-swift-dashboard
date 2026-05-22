# =============================================================================
# R/mod_animation.R - Merged map (static + server-side animation)
# -----------------------------------------------------------------------------
# Server-side animation pattern. Optimized for ultra-smooth playback by
# drawing ONLY the active tracking points and trails at any given hour.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(leaflet)
  library(leaflet.extras)
  library(dplyr)
  library(ggplot2)
  library(plotly)
  library(htmltools)
  library(lubridate)
  library(sf)
})

animation_ui <- function(id) {
  ns <- NS(id)
  tagList(
    # --- LAYOUT: Map on Left (8/12), Controls on Right (4/12) ---
    bslib::layout_columns(
      col_widths = c(8, 4),
      
      card(
        full_screen = TRUE,
        leafletOutput(ns("anim_map"), height = "65vh"),
        div(class = "small text-muted px-2 pt-2",
            "Top-right of the map: toggle Tracking points / Colony residence. Click any point for details.")
      ),
      
      card(
        card_header(span("Playback Controls", class = "panel-heading fw-bold")),
        card_body(
          div(class = "d-flex justify-content-between mb-3",
              actionButton(ns("playBtn"), label = "▶ Play", class = "btn-success flex-grow-1 me-2"),
              actionButton(ns("resetBtn"), label = "↺ Reset", class = "btn-outline-secondary flex-grow-1 ms-2")
          ),
          
          div(class = "text-center fs-5 fw-bold text-success mb-2",
              textOutput(ns("date_label"), inline = TRUE)
          ),
          
          sliderInput(ns("doy"), label = NULL,
                      min = 1, max = 365, value = 100, step = 0.5,
                      width = "100%"),
          hr(),
          
          radioButtons(ns("speed_choice"), "Speed",
                       choices = c("Slow"   = "slow",
                                   "Medium" = "med",
                                   "Fast"   = "fast"),
                       selected = "med", inline = TRUE),
          radioButtons(ns("trail_choice"), "Sperm trail",
                       choices = c("Off"  = 0,
                                   "12 h" = 2,
                                   "24 h" = 4,
                                   "72 h" = 12),
                       selected = 0, inline = TRUE),
          hr(),
          
          div(class = "small text-muted",
              textOutput(ns("counter"), inline = TRUE))
        )
      )
    ),
    
    # --- BOTTOM: The Interactive Plotly Plots ---
    fluidRow(
      column(6,
        card(
          card_header(span("Latitude of active tracking points", class = "panel-subheading")),
          plotlyOutput(ns("anim_lat_curve"), height = "260px"),
          p(class = "small text-muted px-2 pb-1", 
            "Distribution of currently tracked birds. Grouped dynamically by the 'Color by' selection.")
        )
      ),
      column(6,
        card(
          card_header(span("Active individuals", class = "panel-subheading")),
          plotlyOutput(ns("anim_count_curve"), height = "260px"),
          p(class = "small text-muted px-2 pb-1", 
            "Count of currently tracked birds. Grouped dynamically by the 'Color by' selection.")
        )
      )
    )
  )
}

animation_server <- function(id, filtered, processed) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    is_playing <- reactiveVal(FALSE)
    anim_mode  <- reactiveVal("overview")

    observeEvent(input$playBtn, {
      new_state <- !is_playing()
      is_playing(new_state)
      if (new_state) anim_mode("animation")
    })

    # Auto-switch to animation mode if the user drags the slider
    observeEvent(input$doy, {
      if (isolate(anim_mode()) == "overview") {
        if (abs(input$doy - 100) > 0.4) anim_mode("animation")
      }
    }, ignoreInit = TRUE)

    observeEvent(input$resetBtn, {
      is_playing(FALSE)
      anim_mode("overview")
      updateSliderInput(session, "doy", value = 100)
    })

    # ---- Animation loop ----------------------------------------------------
    observe({
      if (!is_playing()) return()
      invalidateLater(200)
      isolate({
        cur  <- input$doy
        if (is.null(cur) || is.na(cur)) cur <- 100
        
        speed_c <- input$speed_choice
        if (is.null(speed_c)) speed_c <- "med"
        step <- switch(speed_c, slow = 0.5, med = 1.5, fast = 4.0)
                       
        new_val <- cur + step
        if (new_val > 365) new_val <- 1
        updateSliderInput(session, "doy", value = new_val)
      })
    })

    plot_doy <- reactive({
      v <- input$doy
      if (is.null(v) || is.na(v)) 100 else as.numeric(v)
    }) |> shiny::throttle(400)

    # ---- Indexed hourly stream ---------------------------------------------
    hourly_indexed <- reactive({
      df <- filtered$hourly_anim()
      if (is.null(df) || nrow(df) == 0) return(NULL)
      
      df <- df |> dplyr::filter(!is.na(lat), !is.na(lon), !is.na(timestamp))
      if (nrow(df) == 0) return(NULL)
      
      df$hoy <- (as.integer(df$doy) - 1L) * 24L + as.integer(lubridate::hour(df$timestamp))
      df
    })

    # ---- Helper: positions at target hour ----------------------------------
    .positions_at <- function(df_idx, target_hour, gm) {
      if (is.null(df_idx) || !"hoy" %in% names(df_idx)) return(NULL)
      
      win <- df_idx[abs(df_idx$hoy - target_hour) <= 6L, , drop = FALSE]
      if (nrow(win) == 0) return(NULL)
      
      win$.d <- abs(win$hoy - target_hour)
      
      win <- win |>
        dplyr::group_by(bird_id, year) |>
        dplyr::slice_min(.d, n = 1L, with_ties = FALSE) |>
        dplyr::ungroup()
        
      if (nrow(win) == 0) return(NULL)
      pal <- resolve_palette(win, gm)
      win$col <- pal$col
      win
    }

    # ---- Current frame data for plots (throttled) --------------------------
    current_frame_data <- reactive({
      df_idx <- hourly_indexed()
      gm     <- filtered$group_mode()
      d_f    <- plot_doy()
      
      if (is.null(df_idx) || nrow(df_idx) == 0) return(NULL)

      target_hour <- as.integer(round((d_f - 1) * 24))
      cur <- .positions_at(df_idx, target_hour, gm)
      
      if (is.null(cur) || nrow(cur) == 0) return(NULL)

      cur$group_col <- switch(gm, country = cur$country, colony = cur$colony_name, flyway = cur$flyway, year = as.character(cur$year))
      attr(cur, "palette_colors") <- resolve_palette(cur, gm)$colors
      cur
    })

    # ---- Date readout ------------------------------------------------------
    output$date_label <- renderText({
      d_f <- input$doy
      if (is.null(d_f) || is.na(d_f)) d_f <- 100
      d_int <- as.integer(floor(d_f))
      hr    <- as.integer(round((d_f - floor(d_f)) * 24)) %% 24
      base  <- as.Date(d_int - 1, origin = "2015-01-01")
      sprintf("%s %02d:00", format(base, "%d %B"), hr)
    })

    # ---- Base map (rendered ONCE) ------------------------------------------
    output$anim_map <- renderLeaflet({
      cs <- processed$colonies
      pal_c <- colorFactor(palette = unname(COUNTRY_COLORS), levels = names(COUNTRY_COLORS))
      
      leaflet(options = leafletOptions(worldCopyJump = FALSE, minZoom = 2, maxZoom = 9, preferCanvas = TRUE)) |>
        addTiles(urlTemplate = BASEMAP_URL, attribution = BASEMAP_ATTR, options = tileOptions(opacity = 0.9)) |>
        fitBounds(lng1 = MAP_BOUNDS$lng1, lat1 = MAP_BOUNDS$lat1, lng2 = MAP_BOUNDS$lng2, lat2 = MAP_BOUNDS$lat2) |>
        addScaleBar(position = "bottomleft", options = scaleBarOptions(imperial = FALSE)) |>
        addCircleMarkers(
          data = cs, lng = ~lon, lat = ~lat,
          radius = ~sqrt(n_birds) * 1.8 + 4, weight = 1.6, color = "#222",
          fillColor = ~pal_c(country), fillOpacity = 0.95, group = "Colony residence", layerId = ~colony_id,
          label = ~sprintf("%s, %s - %d birds", colony_name, country, n_birds),
          popup = ~sprintf("<b>%s</b><br/>%s &middot; %s flyway<br/>n = %d birds", htmltools::htmlEscape(colony_name), htmltools::htmlEscape(country), htmltools::htmlEscape(flyway), n_birds)
        ) |>
        addLayersControl(
          overlayGroups = c("Tracking points", "Colony residence"),
          options = layersControlOptions(collapsed = FALSE, autoZIndex = TRUE)
        )
    })

    # ---- Dynamic Legend Setup ----------------------------------------------
    observe({
      df <- filtered$hourly_anim()
      gm <- filtered$group_mode()
      if (is.null(df) || nrow(df) == 0) return()
      pal <- resolve_palette(df, gm)
      
      leafletProxy(ns("anim_map")) |> addControl(
        html = render_map_legend(pal, extra_row = '<div class="legend-row"><span class="legend-swatch legend-ring"></span>Breeding colony (size = n birds)</div>'),
        position = "topright", layerId = "legend", className = "map-legend-wrap"
      )
    })

    # ---- Tracking Points & Trails (Handles Overview vs Animation) ----------
    observe({
      proxy <- leafletProxy(ns("anim_map"))
      proxy |> clearGroup("Tracking points")

      df_idx <- hourly_indexed()
      gm     <- filtered$group_mode()
      mode   <- anim_mode()
      
      if (is.null(df_idx) || nrow(df_idx) == 0) return()

      # =======================================================================
      # SCENARIO 1: OVERVIEW MODE (Show all points, no trails)
      # =======================================================================
      if (identical(mode, "overview")) {
        pal <- resolve_palette(df_idx, gm)
        
        bg <- df_idx
        bg$col <- pal$col

        n_max <- 8000L
        if (nrow(bg) > n_max) bg <- bg[sample(nrow(bg), n_max), ]

        proxy |> addCircleMarkers(
          data = bg, lng = ~lon, lat = ~lat, 
          radius = ~ifelse(phase == "migration", 3.2, 2.4),
          color = ~col, fillColor = ~col, stroke = FALSE, 
          fillOpacity = 0.40, group = "Tracking points",
          popup = ~sprintf("<b>%s</b> &middot; %s<br/>Bird: <code>%s</code> (yr %s)<br/>%s &middot; %s", 
                           htmltools::htmlEscape(colony_name), htmltools::htmlEscape(country), 
                           htmltools::htmlEscape(bird_id), htmltools::htmlEscape(as.character(year)), 
                           format(date, "%Y-%m-%d"), stage_label(phase))
        )
        return()
      }

      # =======================================================================
      # SCENARIO 2: ANIMATION MODE (Show only active points & trails)
      # =======================================================================
      d_f <- input$doy
      if (is.null(d_f) || is.na(d_f)) d_f <- 100
      
      target_hour <- as.integer(round((d_f - 1) * 24))
      cur <- .positions_at(df_idx, target_hour, gm)
      
      if (!is.null(cur) && nrow(cur) > 0) {
        
        # 1. Plot current active birds
        proxy |> addCircleMarkers(
          data = cur, lng = ~lon, lat = ~lat, radius = 6.2, color = ~col, fillColor = ~col,
          stroke = FALSE, fillOpacity = 0.95, group = "Tracking points",
          label = ~sprintf("%s | %s | %s", colony_name, format(date, "%d %b %Y"), stage_label(phase)),
          popup = ~sprintf("<b>%s</b> &middot; %s<br/>Bird: <code>%s</code> (yr %s)<br/>%s &middot; %s", 
                           htmltools::htmlEscape(colony_name), htmltools::htmlEscape(country), 
                           htmltools::htmlEscape(bird_id), htmltools::htmlEscape(as.character(year)), 
                           format(date, "%Y-%m-%d"), stage_label(phase))
        )
      }

      # 3. Process Sperm Trails
      trail_c <- input$trail_choice
      if (is.null(trail_c)) trail_c <- 0L
      trail <- as.integer(trail_c)
      
      if (trail > 0) {
        trail_pts_list <- lapply(seq_len(trail), function(j) {
          th <- target_hour - 6L * j
          p <- .positions_at(df_idx, th, gm)
          if (!is.null(p) && nrow(p) > 0) {
            p$age_step <- j
            p
          } else NULL
        })
        trail_pts <- dplyr::bind_rows(Filter(Negate(is.null), trail_pts_list))

        if (nrow(trail_pts) > 0) {
          trail_pts <- trail_pts |>
            dplyr::mutate(
              age_frac = age_step / (trail + 1),
              .alpha   = pmax(0.25, 0.85 * (1 - age_frac)),
              .radius  = pmax(1.4, 3.2 * (1 - age_frac))
            )
          proxy |> addCircleMarkers(
            data = trail_pts, lng = ~lon, lat = ~lat, radius = ~.radius,
            color = ~col, fillColor = ~col, stroke = FALSE, fillOpacity = ~.alpha, 
            group = "Tracking points"
          )
        }

        all_pts_list <- list()
        if (!is.null(cur) && nrow(cur) > 0) {
          cur2 <- cur |> dplyr::mutate(age_step = 0L)
          all_pts_list[[1]] <- cur2[, c("bird_id", "year", "country", "colony_name", "flyway", "lat", "lon", "col", "age_step")]
        }
        if (nrow(trail_pts) > 0) {
          all_pts_list[[2]] <- trail_pts[, c("bird_id", "year", "country", "colony_name", "flyway", "lat", "lon", "col", "age_step")]
        }
        
        all_pts <- dplyr::bind_rows(all_pts_list)

        if (nrow(all_pts) > 0) {
          groups <- split(all_pts, paste(all_pts$bird_id, all_pts$year, sep = "|"))
          groups <- groups[vapply(groups, nrow, integer(1)) >= 2L]
          
          if (length(groups) > 0) {
            geoms <- lapply(groups, function(g) {
              g <- g[order(g$age_step), , drop = FALSE]
              sf::st_linestring(cbind(as.numeric(g$lon), as.numeric(g$lat)))
            })
            meta <- do.call(rbind, lapply(groups, function(g) {
              g[1, c("bird_id", "year", "country", "colony_name", "flyway", "col"), drop = FALSE]
            }))
            trail_sf <- sf::st_sf(meta, geometry = sf::st_sfc(geoms, crs = 4326))
            
            proxy |> addPolylines(
              data = trail_sf, color = ~col, weight = 1.4, opacity = 0.65, 
              group = "Tracking points"
            )
          }
        }
      }
    })

    # ---- Plots: Latitude Boxplot -------------------------------------------
    output$anim_lat_curve <- renderPlotly({ suppressWarnings({
      cur <- current_frame_data()
      shiny::validate(need(!is.null(cur) && nrow(cur) > 0, "No active tracking data for this exact time."))

      colors <- attr(cur, "palette_colors")

      p <- ggplot(cur, aes(x = group_col, y = lat, fill = group_col,
                           text = sprintf("Bird: %s<br>Lat: %.1f°N", bird_id, lat))) +
        geom_boxplot(alpha = 0.7, outlier.shape = NA) +
        geom_jitter(width = 0.2, size = 1.5, alpha = 0.7, color = "#222") +
        geom_hline(yintercept = 23.4366, linetype = "dashed", color = "#888", linewidth = 0.4) +
        scale_fill_manual(values = colors) +
        scale_y_continuous(limits = c(-15, 60)) +
        labs(x = NULL, y = "Latitude (°N)") +
        theme_minimal(base_size = 11) +
        theme(legend.position = "none",
              panel.grid.minor = element_blank())

      ggplotly(p, tooltip = "text") %>%
        plotly::config(displayModeBar = TRUE, scrollZoom = TRUE) %>%
        plotly::layout(showlegend = FALSE, margin = list(b = 40))
    }) })

    # ---- Plots: Active Count Bar Chart -------------------------------------
    output$anim_count_curve <- renderPlotly({ suppressWarnings({
      cur <- current_frame_data()
      shiny::validate(need(!is.null(cur) && nrow(cur) > 0, "No active tracking data for this exact time."))

      colors <- attr(cur, "palette_colors")
      max_birds <- length(unique(filtered$daily_anim()$bird_id))

      counts <- cur %>%
        dplyr::group_by(group_col) %>%
        dplyr::summarise(n = dplyr::n(), .groups = "drop")

      p <- ggplot(counts, aes(x = group_col, y = n, fill = group_col,
                              text = sprintf("%s<br>Active: %d birds", group_col, n))) +
        geom_col(alpha = 0.85, color = "#222", linewidth = 0.3) +
        scale_fill_manual(values = colors) +
        scale_y_continuous(limits = c(0, max(5, max_birds)), expand = expansion(mult = c(0, 0.05))) +
        labs(x = NULL, y = "Active individuals") +
        theme_minimal(base_size = 11) +
        theme(legend.position = "none",
              panel.grid.minor = element_blank())

      ggplotly(p, tooltip = "text") %>%
        plotly::config(displayModeBar = TRUE, scrollZoom = TRUE) %>%
        plotly::layout(showlegend = FALSE, margin = list(b = 40))
    }) })

    output$counter <- renderText({
      df <- filtered$hourly_anim()
      n_inst <- if (is.null(df) || nrow(df) == 0) 0 else dplyr::n_distinct(paste(df$bird_id, df$year))
      n_birds <- if (is.null(df) || nrow(df) == 0) 0 else dplyr::n_distinct(df$bird_id)
      sprintf("%s bird-year instances (%s unique birds) in selection.", fmt_int(n_inst), fmt_int(n_birds))
    })

    observeEvent(is_playing(), {
      updateActionButton(session, "playBtn", label = if (is_playing()) "⏸ Pause" else "▶ Play")
    })
  })
}