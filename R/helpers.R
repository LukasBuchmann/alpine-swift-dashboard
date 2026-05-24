# =============================================================================
# R/helpers.R - shared utilities (palettes, formatters, cartographic config)
# -----------------------------------------------------------------------------
# Cartographic principles applied (after Slocum et al., Thematic Cartography
# and Geovisualization, 3rd ed.):
#   * Visual hierarchy: subdued grey basemap, thematic symbols dominate.
#   * Sequential data:  perceptually uniform ramps (viridis / cividis),
#                       NEVER rainbow/spectral.
#   * Qualitative data: ColorBrewer-style palette, restricted to <= 8 hues,
#                       colorblind-tested (Okabe-Ito derived).
#   * Diverging data:   reserved for centered measurements (not used).
#   * Symbol scaling:   area-proportional (sqrt(n)) for quantities.
# =============================================================================

suppressPackageStartupMessages({
  library(RColorBrewer)
  library(viridisLite)
  library(scales)
})

# ---- Qualitative palette: 4 populations (Okabe-Ito-derived, CB-safe) -------
# Switzerland = teal-green (subdued, central population)
# Spain       = warm orange (western, southern, distinct from CH)
# Bulgaria    = deep purple (eastern, contrasts with CH/ES)
# Turkey      = burnt sienna (eastern, distinct from BG, less saturated than
#               the previous magenta which was too aggressive for science viz)
# ColorBrewer "Dark2" - the canonical qualitative palette Slocum (ch.14)
# recommends for nominal categorical data. Colour-blind-tested, print-safe.
COUNTRY_COLORS <- c(
  "Switzerland" = "#1B9E77",   # Dark2-1 teal
  "Spain"       = "#D95F02",   # Dark2-2 orange
  "Bulgaria"    = "#7570B3",   # Dark2-3 purple
  "Turkey"      = "#E7298A"    # Dark2-4 magenta
)

# Flyway: same Dark2 family as the country palette so the colour scheme
# is consistent whether the user groups by country or by flyway.
FLYWAY_COLORS <- c(
  "western" = "#1B9E77",   # Dark2-1 teal
  "eastern" = "#D95F02"    # Dark2-2 orange
)

# Year: ColorBrewer "YlGnBu" 3-step (sequential, Slocum ch.14 - ordinal data
# needs a sequential ramp, not a qualitative one).
YEAR_COLORS <- c(
  "2014" = "#EDF8B1",
  "2015" = "#7FCDBB",
  "2016" = "#2C7FB8"
)

# Phase colors (nominal, but consistent with annual-cycle order)
PHASE_COLORS <- c(
  "breeding"   = "#1B7837",   # forest green
  "migration"  = "#E08214",   # amber (transit)
  "wintering"  = "#542788"    # deep purple (residence in tropics)
)

# Sequential ramp for time / count (perceptually uniform, colorblind-safe)
SEQ_RAMP <- function(n = 9, option = "viridis") {
  viridisLite::viridis(n, option = option, direction = 1, end = 0.95)
}

# Subdued base map (CartoDB Positron) - pale grey, low chroma. The pale
# basemap is intentional: figure / ground principle (Slocum ch. 12) means
# the thematic symbols (bird tracks) must dominate, not the substrate.
BASEMAP_URL <- "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
BASEMAP_ATTR <- paste0(
  "&copy; <a href=\"https://www.openstreetmap.org/copyright\">OpenStreetMap</a> ",
  "contributors &copy; <a href=\"https://carto.com/attributions\">CARTO</a>"
)

# Map extent: covers all breeding colonies + entire trans-Saharan migration
# corridor down to the wintering grounds at 5 N.
MAP_BOUNDS <- list(
  lng1 = -18, lat1 = -5,
  lng2 =  45, lat2 = 55
)

# Day-of-year helpers
doy_to_md <- function(doy) {
  format(as.Date(doy - 1, origin = "2015-01-01"), "%b %d")
}
doy_to_long <- function(doy) {
  format(as.Date(doy - 1, origin = "2015-01-01"), "%d %B")
}

stage_label <- function(phase) {
  tools::toTitleCase(phase)
}

# Quick formatter for big integers
fmt_int <- function(x) format(x, big.mark = " ", scientific = FALSE)

# ---- Shared "color by" palette resolver ------------------------------------
# Used by both the static map and the animated map so the colour scheme is
# consistent and the legend always matches what is drawn.
#
# Returns a list:
#   levels  -> character vector of category labels (sorted)
#   colors  -> named character vector keyed by levels (the palette)
#   cat     -> character vector aligned with df rows (the category each row
#              belongs to under the current grouping)
#   col     -> character vector aligned with df rows (the colour of each row)
#   title   -> short legend title for the grouping
resolve_palette <- function(df, gm) {
  if (nrow(df) == 0) {
    return(list(levels = character(0), colors = character(0),
                cat = character(0), col = character(0),
                title = "Population"))
  }
  levels <- switch(gm,
                   country = sort(unique(df$country)),
                   colony  = sort(unique(df$colony_name)),
                   flyway  = c("western", "eastern"),
                   year    = sort(unique(as.character(df$year))))
  colors <- switch(
    gm,
    country = COUNTRY_COLORS[levels],
    colony  = setNames(
      grDevices::colorRampPalette(
        suppressWarnings(RColorBrewer::brewer.pal(8, "Dark2"))
      )(length(levels)),
      levels),
    flyway  = FLYWAY_COLORS[levels],
    year    = YEAR_COLORS[levels])
  # Defensive: any unknown category gets a neutral grey
  colors[is.na(colors)] <- "#999999"

  cat_vec <- switch(gm,
                    country = df$country,
                    colony  = df$colony_name,
                    flyway  = df$flyway,
                    year    = as.character(df$year))
  # IMPORTANT: unname the per-row colours. If we leave the names on,
  # jsonlite serialises the vector as a JSON OBJECT (collapsing duplicate
  # category names to a single key) and every Leaflet marker ends up
  # with the same colour. unname() forces an unnamed vector -> JSON array.
  col_vec <- unname(colors[cat_vec])
  col_vec[is.na(col_vec)] <- "#999999"

  list(levels = levels, colors = colors,
       cat = unname(cat_vec), col = col_vec,
       title = switch(gm,
                      country = "Population",
                      colony  = "Colony",
                      flyway  = "Flyway",
                      year    = "Year"))
}

# Render the palette as an HTML legend (shared between map modules).
render_map_legend <- function(pal, extra_row = NULL) {
  if (length(pal$levels) == 0) {
    return(htmltools::HTML(
      '<div class="map-legend"><div class="legend-title">No data</div></div>'))
  }
  rows <- mapply(function(lvl, col) {
    sprintf('<div class="legend-row"><span class="legend-swatch" style="background:%s"></span>%s</div>',
            col, htmltools::htmlEscape(lvl))
  }, pal$levels, pal$colors, USE.NAMES = FALSE)
  htmltools::HTML(sprintf(
    '<div class="map-legend">
       <div class="legend-title">%s</div>
       %s
       %s
     </div>',
    pal$title,
    paste(rows, collapse = "\n"),
    if (is.null(extra_row)) "" else
      paste0("<hr/>", extra_row)
  ))
}
