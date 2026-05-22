#!/usr/bin/env Rscript
# =============================================================================
# build_anim_data.R
# Run ONCE (or whenever the source CSVs change).
#
# Outputs
#   www/anim_data.js   — static JS file served directly by Shiny HTTP,
#                        browser-cached, zero WebSocket cost per session
#   data/app_data.rds  — R-side data for plots, loaded in <1 s at app start
# =============================================================================
cat("=== build_anim_data.R ===\n")
t0 <- proc.time()

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

# Locate project directory
args <- commandArgs(trailingOnly = FALSE)
fa   <- grep("--file=", args, value = TRUE)
SCRIPT_DIR <- if (length(fa)) {
  dirname(normalizePath(sub("--file=", "", fa[1]), mustWork = FALSE))
} else {
  getwd()
}

DATA_DIR <- file.path(SCRIPT_DIR, "data")
WWW_DIR  <- file.path(SCRIPT_DIR, "www")
dir.create(WWW_DIR, showWarnings = FALSE)

SPERM_N  <- 10L
WINDOW_D <- 7L    # trailing-window days for locs_snap

# ---- Colony colour table (matches swift_data.json) -------------------------
# CARTOGRAPHY NOTE: Colonies are *nominal* (unordered) data. Slocum et al.
# Ch.10 warns against sequential single-hue palettes for nominal categories
# because identical hues imply ordering/similarity. We use a 9-hue qualitative
# palette (perceptually balanced, derived from Tableau's qualitative set) that
# assigns distinct, equally-prominent hues across all colonies, eliminating the
# visual hierarchy produced by the previous blue-only sequential scheme.
COLONY_COLORS <- c(
  "Switzerland Baden"     = "#4e79a7",  # Tableau steel-blue
  "Switzerland Biel"      = "#59a14f",  # Tableau forest-green
  "Switzerland Lausanne"  = "#b07aa1",  # Tableau muted-purple
  "Switzerland Lenzburg"  = "#76b7b2",  # Tableau teal
  "Switzerland Luzern"    = "#9c755f",  # Tableau warm-brown
  "Switzerland Solothurn" = "#499894",  # Tableau cyan-teal
  "Spain Tarragona"       = "#e15759",  # Tableau vivid-red
  "Bulgaria Sofia"        = "#f28e2b",  # Tableau vivid-orange
  "Turkey Pirasali"       = "#d37295"   # deep magenta
)
unique_colonies <- sort(names(COLONY_COLORS))

# =============================================================================
# 1. Read all CSVs with fread (5-10x faster than read.csv)
# =============================================================================
cat("Reading CSVs...\n")
csv_files <- list.files(DATA_DIR, pattern = "\\.csv$", full.names = TRUE)
cat("  Found:", length(csv_files), "files\n")

KEEP_COLS <- c("timestamp", "location-lat", "location-long",
               "lat-lower", "lat-upper", "long-lower", "long-upper",
               "individual-local-identifier", "study-name")

raw <- rbindlist(lapply(csv_files, function(f) {
  fread(f, select = KEEP_COLS, showProgress = FALSE)
}), fill = TRUE)
cat("  Rows read:", format(nrow(raw), big.mark = ","), "\n")

# =============================================================================
# 2. Clean & compute midpoint positions
# =============================================================================
cat("Cleaning...\n")
setnames(raw, 
  old = c("location-lat","location-long","lat-lower","lat-upper",
          "long-lower","long-upper","individual-local-identifier","study-name"),
  new = c("raw_lat","raw_lon","lat_lo","lat_hi",
          "lon_lo","lon_hi","bird_id","study"))

# Colony = text before " - Long term..."
raw[, colony := sub(" - Long term.*$", "", study)]
raw[, study  := NULL]

# Midpoint of the geolocator uncertainty interval
raw[, lat := (lat_lo + lat_hi) / 2]
raw[, lon := (lon_lo + lon_hi) / 2]
raw[, c("raw_lat","raw_lon","lat_lo","lat_hi","lon_lo","lon_hi") := NULL]

# Parse to POSIXct to KEEP time (preserves sunrise/sunset separation)
raw[, timestamp := as.POSIXct(timestamp, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")]

# Spatial filter
raw <- raw[!is.na(lat) & !is.na(lon) & 
           lon >= -30 & lon <= 65 & lat >= -20 & lat <= 75]

# Deduplicate only EXACT same-second timestamps per bird 
# (This safely keeps sunrise and sunset separate)
raw <- raw[, .(lat = mean(lat), lon = mean(lon)), 
           by = .(bird_id, colony, timestamp)]

setorder(raw, bird_id, timestamp)
cat("  Clean rows:", format(nrow(raw), big.mark = ","), 
    "| Birds:", uniqueN(raw$bird_id), "\n")

# =============================================================================
# 3. Per-bird visual jitter (reproducible seed matches app)
# =============================================================================
set.seed(42)
birds_uniq <- sort(unique(raw$bird_id))
jitter <- data.table(
  bird_id = birds_uniq,
  jit_lat = runif(length(birds_uniq), -0.12, 0.12),
  jit_lon = runif(length(birds_uniq), -0.12, 0.12)
)
raw <- jitter[raw, on = "bird_id"]
raw[, map_lat := lat + jit_lat]
raw[, map_lon := lon + jit_lon]
raw[, plot_lat := lat]
raw[, c("jit_lat","jit_lon") := NULL]

# =============================================================================
# 4. Daily-interpolated track (for sperm trails and full-path overlay)
# =============================================================================
cat("Interpolating daily tracks...\n")
interp_list <- lapply(split(raw, raw$bird_id), function(bd) {
  bd <- bd[order(bd$timestamp)]
  if (nrow(bd) < 2L) return(NULL)
  d_seq <- seq(min(bd$timestamp), max(bd$timestamp), by = "12 hours")
  d_num <- as.numeric(d_seq)
  data.table(
    bird_id   = bd$bird_id[1L],
    colony    = bd$colony[1L],
    timestamp = d_seq,
    map_lat   = approx(as.numeric(bd$timestamp), bd$map_lat, xout = d_num)$y,
    map_lon   = approx(as.numeric(bd$timestamp), bd$map_lon, xout = d_num)$y,
    lat       = approx(as.numeric(bd$timestamp), bd$lat,     xout = d_num)$y,
    lon       = approx(as.numeric(bd$timestamp), bd$lon,     xout = d_num)$y,
    plot_lat  = approx(as.numeric(bd$timestamp), bd$plot_lat,xout = d_num)$y
  )
})
swift_interp <- rbindlist(Filter(Negate(is.null), interp_list))
swift_interp <- swift_interp[!is.na(map_lat) & !is.na(map_lon)]
setorder(swift_interp, bird_id, timestamp)
cat("  Interp rows:", format(nrow(swift_interp), big.mark = ","), "\n")

swift_clean  <- as.data.frame(raw)

# =============================================================================
# 5. Date range
# =============================================================================
all_dates_vec <- seq(min(raw$timestamp), max(raw$timestamp), by = "12 hours")
cat("  Date range:", as.character(min(all_dates_vec)),
    "->", as.character(max(all_dates_vec)),
    "(", length(all_dates_vec), "days)\n")

# =============================================================================
# 6. locs_snap — most-recent fix per bird within WINDOW_D trailing days
# =============================================================================
cat("Computing locs_snap...\n")
.bf    <- split(raw, raw$bird_id)
.bf_ts <- lapply(.bf, function(x) as.numeric(x$timestamp))

locs_snap <- setNames(lapply(all_dates_vec, function(d) {
  d_num <- as.numeric(d); d7 <- d_num - (WINDOW_D * 86400)
  rows  <- lapply(seq_along(.bf), function(i) {
    idx <- findInterval(d_num, .bf_ts[[i]])
    if (idx == 0L || .bf_ts[[i]][idx] < d7) return(NULL)
    as.data.frame(.bf[[i]][idx, ])
  })
  do.call(rbind, Filter(Negate(is.null), rows))
}), as.character(all_dates_vec))

# =============================================================================
# 7. sp_snap — last SPERM_N interpolated positions per bird
# =============================================================================
cat("Computing sp_snap...\n")
.bi    <- split(swift_interp, swift_interp$bird_id)
.bi_ts <- lapply(.bi, function(x) as.numeric(x$timestamp))

sp_snap <- setNames(lapply(all_dates_vec, function(d) {
  d_num <- as.numeric(d)
  rows  <- lapply(seq_along(.bi), function(i) {
    idx <- findInterval(d_num, .bi_ts[[i]])
    if (idx == 0L) return(NULL)
    as.data.frame(.bi[[i]][max(1L, idx - SPERM_N + 1L):idx, ])
  })
  do.call(rbind, Filter(Negate(is.null), rows))
}), as.character(all_dates_vec))

# =============================================================================
# 8. Compact JS animation data  [lat, lon, colony_idx, bird_id] per bird
# =============================================================================
cat("Serialising JS animation data...\n")
colony_hex_vec <- unname(COLONY_COLORS[unique_colonies])

.jsnap <- lapply(all_dates_vec, function(d) {
  df <- locs_snap[[as.character(d)]]
  if (is.null(df) || nrow(df) == 0L) return(list())
  lapply(seq_len(nrow(df)), function(k)
    list(round(df$map_lat[k], 4L),
         round(df$map_lon[k], 4L),
         match(df$colony[k], unique_colonies) - 1L,
         df$bird_id[k]))
})

JS_ANIM_DATA <- list(
  dates    = as.list(as.character(all_dates_vec)),
  colors   = as.list(colony_hex_vec),
  colNames = as.list(unique_colonies),  # for client-side colony filtering
  snaps    = .jsnap
)

js_out <- file.path(WWW_DIR, "anim_data.js")
writeLines(
  paste0("window._ANIM_DATA=", toJSON(JS_ANIM_DATA, auto_unbox = TRUE), ";"),
  js_out
)
cat("  www/anim_data.js:", round(file.size(js_out) / 1e6, 2), "MB\n")

# =============================================================================
# 9. Save R-side app data (compress=FALSE -> fastest possible readRDS)
# =============================================================================
cat("Saving app_data.rds...\n")
rds_out <- file.path(DATA_DIR, "app_data.rds")
saveRDS(list(
  swift_clean     = swift_clean,
  swift_interp    = as.data.frame(swift_interp),
  locs_snap       = locs_snap,
  sp_snap         = sp_snap,
  colony_colors   = COLONY_COLORS,
  unique_colonies = unique_colonies,
  unique_birds    = sort(unique(swift_clean$bird_id)),
  all_dates_vec   = all_dates_vec
), rds_out, compress = FALSE)
cat("  data/app_data.rds:", round(file.size(rds_out) / 1e6, 2), "MB\n")

elapsed <- round((proc.time() - t0)[["elapsed"]], 1)
cat("=== Done in", elapsed, "s ===\n")
cat("Next: run shinyApp(ui, server) in app.ipynb — startup is now <2 s.\n")
