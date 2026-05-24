# =============================================================================
# R/mod_animation.R - Merged map (static + server-side animation)
# -----------------------------------------------------------------------------
# Implements the Meier et al. 2020 Figure 1 visualisation language:
#
#   * Path-resample dots (low alpha): every retained fix is drawn at once.
#     We never interpolate fake positions between sparse / jittery samples;
#     we instead overlay many samples to convey the credible path.
#   * Migration phase: vertical "shadow strokes" running from the per-day
#     lat_lo to lat_hi credible band visualise the well-known latitudinal
#     uncertainty of light-level geolocators, instead of a hard line.
#   * Moving-point trail (sperm trail): optional polyline trailing each
#     active individual through the last N days of the cycle.
#   * Current day: slightly translucent bright markers, drawn on its own
#     pane so it is ALWAYS on top of every other layer.
#   * Colour is decoupled from data: changing "Color by" only repaints
#     existing dots and updates the on-map legend.
#   * Clicking a point selects the bird and draws its full bird-year track;
#     clicking the same bird again deselects.
# =============================================================================
suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(leaflet)
  library(dplyr)
  library(ggplot2)
  library(plotly)
  library(sf)
  library(htmltools)
})

animation_ui <- function(id) {
  ns <- NS(id)
  tagList(
    bslib::layout_columns(
      col_widths = c(8, 4),
      card(
        full_screen = TRUE,
        leafletOutput(ns("anim_map"), height = "65vh"),
        div(class = "plot-caption",
            "Trans-Saharan annual cycle of Alpine Swifts. ",
            "Each dot is one retained daily fix (alpha-blended path ",
            "resamples); brighter circles mark the slider's current ",
            "day. Vertical strokes show the per-bird 10-90 percentile ",
            "latitudinal uncertainty band during migration. ",
            "Toggle layers top-right; click a dot to highlight that ",
            "bird; click again to deselect.")
      ),
      card(
        card_header(span("Playback Controls",
                         class = "panel-heading fw-bold")),
        card_body(
          div(class = "d-flex justify-content-between mb-3",
              actionButton(ns("playBtn"), label = "Play",
                           class = "btn-success flex-grow-1 me-2"),
              actionButton(ns("resetBtn"), label = "Reset",
                           class = "btn-outline-secondary flex-grow-1 ms-2")
          ),
          div(class = "text-center fs-5 fw-bold text-success mb-2",
              textOutput(ns("date_label"), inline = TRUE)),
          sliderInput(ns("doy"), label = NULL,
                      min = 1, max = 365, value = 100, step = 1,
                      width = "100%"),
          hr(),
          radioButtons(ns("speed_choice"), "Speed",
                       choices  = c("Slow" = "slow", "Medium" = "med",
                                    "Fast" = "fast"),
                       selected = "med", inline = TRUE),
          radioButtons(ns("trail_choice"), "Moving-point trail",
                       choices  = c("Off" = 0, "1 day" = 1,
                                    "3 days" = 3, "7 days" = 7),
                       selected = 0, inline = TRUE),
          hr(),
          h6("Selected individual", class = "panel-subheading"),
          uiOutput(ns("bird_card"))
        )
      )
    ),
    fluidRow(
      column(12,
             card(card_header("Latitude of active individuals"),
                  plotlyOutput(ns("anim_lat_curve"), height = "260px"),
                  div(class = "plot-caption",
                      "Boxplot of latitude (degrees N) for every bird ",
                      "active on the slider's day-of-year, grouped by ",
                      "the active 'Color by' category. Whiskers extend ",
                      "to 1.5x IQR; jitter points show individual fixes."))
      )
    )
  )
}

animation_server <- function(id, filtered, processed) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    is_playing <- reactiveVal(FALSE)
    sel_bird   <- reactiveVal(NULL)

    observeEvent(input$playBtn, { is_playing(!is_playing()) })
    observeEvent(input$resetBtn, {
      is_playing(FALSE)
      sel_bird(NULL)
      updateSliderInput(session, "doy", value = 100)
    })

    observe({
      if (!is_playing()) return()
      invalidateLater(200)
      isolate({
        cur  <- input$doy %||% 100
        step <- switch(input$speed_choice %||% "med",
                       slow = 1, med = 3, fast = 7)
        new_val <- if (cur + step > 365) 1 else cur + step
        updateSliderInput(session, "doy", value = new_val)
      })
    })

    plot_doy <- reactive({ as.numeric(input$doy %||% 100) }) |>
      shiny::throttle(350)

    # ---- Current-frame slice (used for highlight + latitude plot) ----------
    current_frame_data <- reactive({
      df <- filtered$daily()
      if (is.null(df) || nrow(df) == 0) return(NULL)
      d_f <- plot_doy()
      cur <- df %>%
        dplyr::filter(abs(doy - d_f) <= 3) %>%
        dplyr::group_by(bird_id, year) %>%
        dplyr::slice(1) %>%
        dplyr::ungroup()
      if (nrow(cur) == 0) return(NULL)
      gm <- filtered$group_mode()
      cur$group_col <- switch(gm,
                              country = cur$country,
                              colony  = cur$colony_name,
                              flyway  = cur$flyway,
                              year    = as.character(cur$year))
      attr(cur, "palette_colors") <- resolve_palette(cur, gm)$colors
      cur
    })

    output$date_label <- renderText({
      format(as.Date(as.integer(input$doy %||% 100) - 1,
                     origin = "2015-01-01"), "%d %B")
    })

    # ---- Initial leaflet skeleton (with explicit z-order panes) ------------
    output$anim_map <- renderLeaflet({
      leaflet(options = leafletOptions(worldCopyJump = FALSE,
                                       minZoom = 2, maxZoom = 9,
                                       preferCanvas = TRUE)) |>
        addTiles(urlTemplate = BASEMAP_URL,
                 attribution = BASEMAP_ATTR,
                 options = tileOptions(opacity = 0.9)) |>
        fitBounds(lng1 = MAP_BOUNDS$lng1, lat1 = MAP_BOUNDS$lat1,
                  lng2 = MAP_BOUNDS$lng2, lat2 = MAP_BOUNDS$lat2) |>
        # Panes: higher zIndex = drawn on top. Current day = top.
        addMapPane("paneShadow",    zIndex = 380) |>
        addMapPane("paneTrail",     zIndex = 410) |>
        addMapPane("paneResamples", zIndex = 425) |>
        addMapPane("paneSelected",  zIndex = 440) |>
        addMapPane("paneCurrent",   zIndex = 470) |>
        addLayersControl(
          overlayGroups = c("Path resamples",
                            "Migration uncertainty",
                            "Moving trail",
                            "Current day",
                            "Selected bird"),
          options = layersControlOptions(collapsed = FALSE,
                                         autoZIndex = FALSE))
    })

    # ---- Map legend (adapts to "Color by") ---------------------------------
    observe({
      df <- filtered$daily()
      gm <- filtered$group_mode()
      proxy <- leafletProxy(ns("anim_map")) %>%
        removeControl("anim_legend")
      if (is.null(df) || nrow(df) == 0) return()
      pal <- resolve_palette(df, gm)
      html <- render_map_legend(pal)
      proxy %>% addControl(html, position = "topright",
                           layerId = "anim_legend")
    })

    # ---- Always-on path resamples (figure-1 dot cloud) ---------------------
    # Repaints when the *data filter* or the *colour mode* changes, but the
    # visible *set of points* is determined only by the data filter -> the
    # "Color by" radio only changes the colours, not the visible dots.
    observe({
      df <- filtered$daily()
      gm <- filtered$group_mode()
      proxy <- leafletProxy(ns("anim_map")) %>%
        clearGroup("Path resamples") %>%
        clearGroup("Migration uncertainty")

      if (is.null(df) || nrow(df) == 0) return()

      pal <- resolve_palette(df, gm)
      df$col <- pal$col

      # Phase-aware alpha: breeding/wintering points are dense -> lower alpha;
      # migration points are sparse -> a bit brighter. All translucent enough
      # that overlapping dots remain visible.
      df$alpha <- ifelse(df$phase == "migration", 0.55, 0.28)

      # Layer 1 - migration uncertainty "shadow strokes".
      mig <- df[df$phase == "migration" &
                  is.finite(df$lat_lo) & is.finite(df$lat_hi) &
                  (df$lat_hi - df$lat_lo) > 0.05, , drop = FALSE]
      if (nrow(mig) > 0) {
        geoms <- lapply(seq_len(nrow(mig)), function(i) {
          sf::st_linestring(rbind(
            c(mig$lon[i], mig$lat_lo[i]),
            c(mig$lon[i], mig$lat_hi[i])))
        })
        unc_sf <- sf::st_sf(col = mig$col,
                            bird_id = mig$bird_id,
                            geometry = sf::st_sfc(geoms, crs = 4326))
        proxy %>% addPolylines(
          data    = unc_sf,
          color   = ~col,
          weight  = 5,
          opacity = 0.10,
          group   = "Migration uncertainty",
          options = pathOptions(interactive = FALSE, pane = "paneShadow"))
      }

      # Layer 2 - path-resample dot cloud (delimiter "##" cannot appear in IDs)
      proxy %>% addCircleMarkers(
        data        = df,
        lng         = ~lon,
        lat         = ~lat,
        layerId     = ~paste("pr", bird_id, year, doy, sep = "##"),
        radius      = ifelse(df$phase == "migration", 3.0, 2.5),
        color       = ~col,
        fillColor   = ~col,
        stroke      = FALSE,
        fillOpacity = df$alpha,
        group       = "Path resamples",
        label       = ~paste0(bird_id, " - ", country,
                              " - ", format(date, "%d %b %Y")),
        options     = pathOptions(pane = "paneResamples"))
    })

    # ---- Moving-point trail (sperm trail) ----------------------------------
    observe({
      proxy <- leafletProxy(ns("anim_map")) %>%
        clearGroup("Moving trail")
      trail_n <- as.integer(input$trail_choice %||% 0)
      if (trail_n <= 0) return()
      df <- filtered$daily()
      gm <- filtered$group_mode()
      if (is.null(df) || nrow(df) == 0) return()

      d_f <- plot_doy()
      # Keep the trail_n days ending on the current day-of-year (wrap-aware:
      # if trail_n is "Full" we keep everything up to the current day).
      paths <- if (trail_n >= 365) {
        df %>% dplyr::filter(doy <= d_f)
      } else {
        df %>% dplyr::filter(doy <= d_f & doy >= (d_f - trail_n))
      }
      if (nrow(paths) == 0) return()

      pal <- resolve_palette(df, gm)
      paths$col <- unname(pal$colors[switch(gm,
                                            country = paths$country,
                                            colony  = paths$colony_name,
                                            flyway  = paths$flyway,
                                            year    = as.character(paths$year))])
      paths$col[is.na(paths$col)] <- "#999999"

      groups <- split(paths, paste(paths$bird_id, paths$year, sep = "|"))
      groups <- groups[vapply(groups, nrow, integer(1)) >= 2L]
      if (length(groups) == 0) return()

      geoms <- lapply(groups, function(g)
        sf::st_linestring(cbind(as.numeric(g$lon), as.numeric(g$lat))))
      meta <- do.call(rbind, lapply(groups,
                                    function(g) g[1, c("bird_id", "col"),
                                                  drop = FALSE]))
      trail_sf <- sf::st_sf(meta,
                            geometry = sf::st_sfc(geoms, crs = 4326))

      proxy %>% addPolylines(
        data    = trail_sf,
        color   = ~col,
        weight  = 2.5,
        opacity = 0.65,
        group   = "Moving trail",
        options = pathOptions(interactive = FALSE, pane = "paneTrail"))
    })

    # ---- Current-day "latest data points" highlight (ALWAYS ON TOP) --------
    observe({
      cur <- current_frame_data()
      proxy <- leafletProxy(ns("anim_map")) %>%
        clearGroup("Current day")
      if (is.null(cur) || nrow(cur) == 0) return()

      pal <- attr(cur, "palette_colors")
      cur_col <- unname(pal[cur$group_col])
      cur_col[is.na(cur_col)] <- "#444444"

      proxy %>% addCircleMarkers(
        data        = cur,
        lng         = ~lon,
        lat         = ~lat,
        layerId     = ~paste("cur", bird_id, year, sep = "##"),
        radius      = 6,
        color       = "#1a1a1a",
        weight      = 0.9,
        fillColor   = cur_col,
        fillOpacity = 0.82,           # slightly translucent
        group       = "Current day",
        label       = ~paste(bird_id, "-", country, "-",
                             format(date, "%d %b %Y")),
        options     = pathOptions(pane = "paneCurrent"))
    })

    # ---- Selected-bird highlight (click toggles selection) -----------------
    observeEvent(input$anim_map_marker_click, {
      m <- input$anim_map_marker_click
      if (is.null(m) || is.null(m$id)) return()
      lid <- as.character(m$id)
      parts <- strsplit(lid, "##", fixed = TRUE)[[1]]
      # Layout: "pr"  -> ["pr",  bird_id, year, doy]
      #         "cur" -> ["cur", bird_id, year]
      #         "sel" -> ["sel", bird_id, year, yyyymmdd]
      bird <- if (length(parts) >= 2) parts[2] else lid
      # Toggle: second click on the same bird clears the selection.
      if (!is.null(sel_bird()) && identical(sel_bird(), bird)) {
        sel_bird(NULL)
      } else {
        sel_bird(bird)
      }
    })

    observe({
      proxy <- leafletProxy(ns("anim_map")) %>%
        clearGroup("Selected bird")
      bird <- sel_bird()
      if (is.null(bird)) return()
      df <- filtered$daily()
      if (is.null(df) || nrow(df) == 0) return()
      track <- df[df$bird_id == bird, , drop = FALSE]
      if (nrow(track) == 0) return()

      track <- track[order(track$year, track$date), ]
      groups <- split(track, paste(track$bird_id, track$year, sep = "|"))
      groups <- groups[vapply(groups, nrow, integer(1)) >= 2L]
      if (length(groups) > 0) {
        geoms <- lapply(groups, function(g)
          sf::st_linestring(cbind(as.numeric(g$lon), as.numeric(g$lat))))
        sel_sf <- sf::st_sf(bird_id = bird,
                            geometry = sf::st_sfc(geoms, crs = 4326))
        proxy %>% addPolylines(data = sel_sf,
                               color = "#111111",
                               weight = 2.4,
                               opacity = 0.85,
                               group  = "Selected bird",
                               options = pathOptions(pane = "paneSelected"))
      }
      proxy %>% addCircleMarkers(
        data        = track,
        lng         = ~lon,
        lat         = ~lat,
        # layerId encodes the same bird so a second click on any yellow
        # waypoint triggers the toggle handler and deselects.
        layerId     = ~paste("sel", bird_id, year,
                             format(date, "%Y%m%d"), sep = "##"),
        radius      = 4,
        color       = "#111111",
        weight      = 1.2,
        fillColor   = "#FFE45E",
        fillOpacity = 0.9,
        group       = "Selected bird",
        label       = ~paste(bird_id, "-", format(date, "%d %b %Y")),
        options     = pathOptions(pane = "paneSelected"))
    })

    # ---- Selected bird details card ---------------------------------------
    output$bird_card <- renderUI({
      bird <- sel_bird()
      if (is.null(bird)) {
        return(div(class = "small text-muted",
                   "Click any dot on the map to highlight that bird's ",
                   "full track and see its details here. Click the same ",
                   "bird again to clear the selection."))
      }
      df <- filtered$daily()
      track <- df[df$bird_id == bird, , drop = FALSE]
      if (nrow(track) == 0) {
        return(div(class = "small text-muted",
                   sprintf("No data for bird %s in current filter.", bird)))
      }
      years <- sort(unique(track$year))
      tagList(
        tags$div(class = "bird-card",
                 tags$div(tags$b(bird)),
                 tags$div(class = "small",
                          sprintf("%s - %s (%s flyway)",
                                  track$colony_name[1], track$country[1],
                                  track$flyway[1])),
                 tags$div(class = "small text-muted",
                          sprintf("%d fixes across %d year(s): %s",
                                  nrow(track), length(years),
                                  paste(years, collapse = ", "))),
                 tags$div(class = "small text-muted",
                          sprintf("Latitude range: %.1f - %.1f deg",
                                  min(track$lat, na.rm = TRUE),
                                  max(track$lat, na.rm = TRUE))),
                 tags$div(class = "small text-muted",
                          sprintf("Phases observed: %s",
                                  paste(sort(unique(track$phase)),
                                        collapse = ", "))),
                 actionLink(ns("clear_sel"), "Clear selection",
                            class = "small mt-1")
        )
      )
    })
    observeEvent(input$clear_sel, { sel_bird(NULL) })

    # ---- Latitude-of-active-individuals plot (single chart) ----------------
    output$anim_lat_curve <- renderPlotly({
      cur <- current_frame_data()
      shiny::validate(need(!is.null(cur) && nrow(cur) > 0,
                           "No active individuals on this day."))
      pal_cols <- attr(cur, "palette_colors")
      p <- ggplot(cur, aes(x = group_col, y = lat, fill = group_col)) +
        geom_boxplot(alpha = 0.7, outlier.shape = NA) +
        geom_jitter(width = 0.2, size = 1.5, alpha = 0.7) +
        scale_fill_manual(values = pal_cols) +
        scale_y_continuous(limits = c(-15, 60)) +
        labs(x = NULL, y = "Latitude (degrees N)") +
        theme_minimal(base_size = 11) +
        theme(legend.position = "none",
              panel.grid.minor = element_blank())
      ggplotly(p) %>% plotly::config(displayModeBar = TRUE)
    })

    observeEvent(is_playing(), {
      updateActionButton(session, "playBtn",
                         label = if (is_playing()) "Pause" else "Play")
    })
  })
}
