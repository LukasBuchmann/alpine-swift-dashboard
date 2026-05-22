# =============================================================================
# R/data_processing.R
# -----------------------------------------------------------------------------
# Cleans raw tracks and computes derived variables.
#   - per-bird annual-cycle phase (mapped from dataset comments)
#   - per-day median position (denoising geolocator wobble)
#   - per-bird phenology summary
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
  library(readr)
  library(tidyr)
  library(geosphere)
  library(zoo) # Added for linear interpolation
})

#' Classify each fix into 'breeding', 'migration' or 'wintering'.
#'
#' Strategy: Direct mapping from the dataset's 'comments' column.
#' Maps "breeding site" -> "breeding"
#'      "non-breeding site" -> "wintering"
#'      "migration" -> "migration"
#' This ensures 100% compatibility with the UI filters and phenology math.
.derive_phase <- function(df) {
  if (!"comments" %in% names(df)) {
    message("Warning: 'comments' column not found in dataset. Defaulting phase to migration.")
    df$phase <- "migration"
    return(df)
  }
  
  df <- df %>%
    dplyr::mutate(
      phase = dplyr::case_when(
        tolower(comments) == "breeding site" ~ "breeding",
        tolower(comments) == "non-breeding site" ~ "wintering",
        tolower(comments) == "migration" ~ "migration",
        TRUE ~ "migration" # Safe fallback for any NAs or strange values
      )
    )
  
  return(df)
}

#' Run the full processing pipeline. Caches outputs to data/processed/.
build_processed_data <- function(force = FALSE) {
  proc_dir <- file.path("data", "processed")
  if (!dir.exists(proc_dir)) dir.create(proc_dir, recursive = TRUE)

  cache <- file.path(proc_dir, "tracks_processed.rds")
  if (file.exists(cache) && !force) {
    message("Using cached processed data: ", cache)
    return(invisible(readRDS(cache)))
  }

  src <- load_tracking_data(prefer_movebank = TRUE)
  tracks <- src$tracks

  # Ensure timestamp is POSIXct, fill in derived time fields
  tracks <- tracks %>%
    dplyr::mutate(
      timestamp = as.POSIXct(timestamp, tz = "UTC"),
      date      = as.Date(timestamp),
      month     = lubridate::month(timestamp),
      year      = as.integer(year)
    )

  # Derive phase directly from the dataset's comments column
  message("Extracting annual-cycle phase from dataset comments...")
  tracks <- .derive_phase(tracks)

  # Helper for safe min/max over a date vector
  safe_min <- function(x) {
    if (length(x) == 0 || all(is.na(x))) as.Date(NA) else min(x, na.rm = TRUE)
  }
  safe_max <- function(x) {
    if (length(x) == 0 || all(is.na(x))) as.Date(NA) else max(x, na.rm = TRUE)
  }

  # Daily median position per bird-day (denoises geolocator scatter)
  message("Aggregating to daily median position...")
  daily <- tracks %>%
    dplyr::group_by(bird_id, colony_id, colony_name, country, flyway,
                    year, date) %>%
    dplyr::summarise(
      lat = median(lat, na.rm = TRUE),
      lon = median(lon, na.rm = TRUE),
      phase = names(sort(table(phase), decreasing = TRUE))[1],
      n_fixes = dplyr::n(),
      .groups = "drop"
    ) %>%
    dplyr::arrange(bird_id, date) %>%
    dplyr::mutate(doy   = lubridate::yday(date),
                  month = lubridate::month(date))

  # -------------------------------------------------------------------------
  # Burst detection
  # -------------------------------------------------------------------------
  # A "burst" is a continuous tracking segment - daily fixes separated by
  # at most MAX_BURST_GAP_DAYS. We only interpolate WITHIN a burst, never
  # across one. This is the scientifically defensible behaviour: a
  # multi-week gap (e.g. tag malfunction, equinox blackout) cannot be
  # filled by a straight line because the bird's actual track during the
  # gap is unknown.
  MAX_BURST_GAP_DAYS <- 14L
  message("Detecting tracking bursts (gap > ", MAX_BURST_GAP_DAYS,
          " days = new burst)...")
  daily <- daily %>%
    dplyr::arrange(bird_id, year, date) %>%
    dplyr::group_by(bird_id, year) %>%
    dplyr::mutate(
      .days_since_prev = as.numeric(difftime(date, dplyr::lag(date),
                                             units = "days")),
      .new_burst       = ifelse(is.na(.days_since_prev) |
                                .days_since_prev > MAX_BURST_GAP_DAYS,
                                1L, 0L),
      burst_id         = cumsum(.new_burst)
    ) %>%
    dplyr::ungroup() %>%
    dplyr::select(-.days_since_prev, -.new_burst)

  # -------------------------------------------------------------------------
  # Hourly Interpolation for Smooth Animation - WITHIN bursts only
  # -------------------------------------------------------------------------
  message("Interpolating daily medians to hourly positions ",
          "(within bursts only)...")
  hourly <- daily %>%
    # Convert the Date to a noon POSIXct timestamp so we have a starting hour
    dplyr::mutate(timestamp = as.POSIXct(paste(date, "12:00:00"),
                                         tz = "UTC")) %>%
    # CRITICAL: group by burst_id so each gap of >14 days breaks the
    # interpolation chain. tidyr::complete() generates the hourly grid
    # only between min and max of each burst, never across.
    dplyr::group_by(bird_id, year, burst_id) %>%
    tidyr::complete(
      timestamp = seq(min(timestamp, na.rm = TRUE),
                      max(timestamp, na.rm = TRUE),
                      by = "hour")
    ) %>%
    dplyr::arrange(bird_id, timestamp) %>%
    dplyr::mutate(
      lat = zoo::na.approx(lat, na.rm = FALSE),
      lon = zoo::na.approx(lon, na.rm = FALSE)
    ) %>%
    tidyr::fill(colony_id, colony_name, country, flyway, phase,
                .direction = "downup") %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      date = as.Date(timestamp),
      doy  = lubridate::yday(timestamp)
    )
  # -------------------------------------------------------------------------

  # Per-bird phenology metrics
  message("Computing per-bird phenology...")
  phenology <- daily %>%
    dplyr::group_by(bird_id, colony_id, country, flyway, year) %>%
    dplyr::summarise(
      breeding_arrival    = safe_min(date[phase == "breeding"]),
      breeding_departure  = safe_max(date[phase == "breeding"]),
      wintering_arrival   = safe_min(date[phase == "wintering" & month >= 9]),
      wintering_departure = safe_max(date[phase == "wintering" & month <= 5]),
      autumn_mig_days     = sum(phase == "migration" & month >= 8, na.rm = TRUE),
      spring_mig_days     = sum(phase == "migration" & month <= 6, na.rm = TRUE),
      n_days_tracked      = dplyr::n(),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      length_of_stay_breeding = as.integer(breeding_departure - breeding_arrival)
    )

  # Per-colony summary
  colony_summary <- daily %>%
    dplyr::group_by(colony_id, colony_name, country, flyway) %>%
    dplyr::summarise(n_birds = dplyr::n_distinct(bird_id),
                     n_fixes = dplyr::n(), .groups = "drop")

  out <- list(
    tracks_raw     = tracks,
    daily          = daily,
    hourly         = hourly, 
    phenology      = phenology,
    colonies       = src$colonies,
    reference      = src$reference,
    colony_summary = colony_summary,
    source         = src$source
  )

  saveRDS(out, cache)
  message("Processed data saved to ", cache,
          "  (", nrow(daily), " daily fixes, ",
          nrow(hourly), " hourly fixes, ", 
          dplyr::n_distinct(daily$bird_id), " birds)")
  invisible(out)
}

#' Quick loader for the app
load_processed <- function() {
  cache <- file.path("data", "processed", "tracks_processed.rds")
  if (!file.exists(cache)) build_processed_data()
  readRDS(cache)
}