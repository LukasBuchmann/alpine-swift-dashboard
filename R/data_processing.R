# =============================================================================
# R/data_processing.R
# -----------------------------------------------------------------------------
# Cleans raw tracks and computes derived variables for the dashboard:
#   - Phase mapping (breeding, migration, wintering) from Movebank `comments`
#   - Airspeed filter (drops fixes that would require > 50 km/h ground speed,
#     comfortably above the Meier 2020 cruising speed of ~12.6 m/s = 45.4 km/h)
#   - Daily-median aggregation (one row per bird per date) so the animated
#     current-day marker is unambiguous.
#   - Rolling per-bird latitudinal uncertainty band (lat_lo / lat_hi / lat_unc)
#     visualised as the migration "shadow" in the animated map.
#   - Per-bird phenology (arrival, departure, length of stay).
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
  library(readr)
  library(geosphere)
})

.derive_phase <- function(df) {
  if (!"comments" %in% names(df)) {
    df$phase <- "migration"
    return(df)
  }
  df %>%
    dplyr::mutate(
      phase = dplyr::case_when(
        tolower(comments) == "breeding site" ~ "breeding",
        tolower(comments) == "non-breeding site" ~ "wintering",
        tolower(comments) == "migration" ~ "migration",
        TRUE ~ "migration"
      )
    )
}

build_processed_data <- function(force = FALSE) {
  proc_dir <- file.path("data", "processed")
  if (!dir.exists(proc_dir)) dir.create(proc_dir, recursive = TRUE)

  cache <- file.path(proc_dir, "tracks_processed.rds")
  if (file.exists(cache) && !force) {
    message("Using cached processed data: ", cache)
    return(invisible(readRDS(cache)))
  }

  src <- load_tracking_data(prefer_movebank = TRUE)
  tracks <- src$tracks %>%
    dplyr::mutate(
      timestamp = as.POSIXct(timestamp, tz = "UTC"),
      date      = as.Date(timestamp),
      month     = lubridate::month(timestamp),
      year      = as.integer(year)
    )

  tracks <- .derive_phase(tracks)

  # Airspeed Filter (Meier 2020 states ~12.6 m/s = ~45.36 km/h)
  message("Filtering impossible geolocator jitter (> 50 km/h buffer)...")
  tracks <- tracks %>%
    dplyr::arrange(bird_id, timestamp) %>%
    dplyr::group_by(bird_id) %>%
    dplyr::mutate(
      time_diff_h = as.numeric(difftime(timestamp, lag(timestamp), units = "hours")),
      dist_km = geosphere::distHaversine(cbind(lon, lat), cbind(lag(lon), lag(lat))) / 1000,
      speed_kmh = dist_km / time_diff_h
    ) %>%
    dplyr::ungroup() %>%
    dplyr::filter(is.na(speed_kmh) | speed_kmh <= 50.0) %>%
    dplyr::select(-time_diff_h, -dist_km, -speed_kmh)

  # ---- Daily-median aggregation ------------------------------------------
  # One row per (bird, date) = the median of all twilight fixes on that day.
  # This is the standard light-level geolocator workflow and keeps the
  # animation's current-day marker unambiguous.
  message("Aggregating to daily median position...")
  daily <- tracks %>%
    dplyr::group_by(bird_id, colony_id, colony_name, country, flyway,
                    year, date) %>%
    dplyr::summarise(
      lat   = median(lat, na.rm = TRUE),
      lon   = median(lon, na.rm = TRUE),
      phase = names(sort(table(phase), decreasing = TRUE))[1],
      .groups = "drop"
    ) %>%
    dplyr::mutate(doy = lubridate::yday(date))

  # ---- Path-uncertainty band (Meier et al. 2020 Figure 1 approach) ---------
  # Geolocators carry an inherent latitudinal error (~150 km, larger near
  # the equinoxes). We approximate this empirically with a 7-day rolling
  # window per bird-year and report a 10-90% credible band around the daily
  # fix - the bounding box used as the "shadow" on the animated map.
  message("Computing per-bird latitudinal uncertainty band (rolling 7d)...")
  .roll_q <- function(x, p) {
    n <- length(x)
    out <- numeric(n)
    for (i in seq_len(n)) {
      lo <- max(1L, i - 3L); hi <- min(n, i + 3L)
      out[i] <- stats::quantile(x[lo:hi], probs = p, na.rm = TRUE, names = FALSE)
    }
    out
  }
  daily <- daily %>%
    dplyr::arrange(bird_id, year, date) %>%
    dplyr::group_by(bird_id, year) %>%
    dplyr::mutate(
      lat_lo = .roll_q(lat, 0.10),
      lat_hi = .roll_q(lat, 0.90),
      lat_unc = pmax(0, lat_hi - lat_lo)
    ) %>%
    dplyr::ungroup()

  # Helper for safe min/max over a date vector
  safe_min <- function(x) {
    if (length(x) == 0 || all(is.na(x))) as.Date(NA) else min(x, na.rm = TRUE)
  }
  safe_max <- function(x) {
    if (length(x) == 0 || all(is.na(x))) as.Date(NA) else max(x, na.rm = TRUE)
  }

  # Phenology math so Figure 3 can calculate duration accurately
  message("Computing per-bird phenology...")
  phenology <- daily %>%
    dplyr::group_by(bird_id, colony_id, country, flyway, year) %>%
    dplyr::summarise(
      breeding_arrival    = safe_min(date[phase == "breeding"]),
      breeding_departure  = safe_max(date[phase == "breeding"]),
      wintering_arrival   = safe_min(date[phase == "wintering" & lubridate::month(date) >= 9]),
      wintering_departure = safe_max(date[phase == "wintering" & lubridate::month(date) <= 5]),
      autumn_mig_days     = sum(phase == "migration" & lubridate::month(date) >= 8, na.rm = TRUE),
      spring_mig_days     = sum(phase == "migration" & lubridate::month(date) <= 6, na.rm = TRUE),
      n_days_tracked      = dplyr::n(),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      length_of_stay_breeding = as.integer(breeding_departure - breeding_arrival)
    )

  colony_summary <- daily %>%
    dplyr::group_by(colony_id, colony_name, country, flyway) %>%
    dplyr::summarise(n_birds = dplyr::n_distinct(bird_id), .groups = "drop")

  out <- list(
    daily          = daily,
    phenology      = phenology,
    colonies       = src$colonies,
    colony_summary = colony_summary,
    source         = src$source
  )

  saveRDS(out, cache)
  message("Processed data saved to ", cache)
  invisible(out)
}

load_processed <- function() {
  cache <- file.path("data", "processed", "tracks_processed.rds")
  if (!file.exists(cache)) build_processed_data()
  readRDS(cache)
}