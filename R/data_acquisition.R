# =============================================================================
# R/data_acquisition.R
# -----------------------------------------------------------------------------
# Loads Alpine Swift tracking data with a layered strategy:
#
#   1. Real Movebank CSVs in data/raw/movebank/*-tracks.csv
#      (downloaded manually from https://datarepository.movebank.org/)
#   2. Movebank live API via the `move` package (requires account)
#   3. Bundled synthetic CSVs in data/raw/tracks.csv (calibrated fallback)
#
# Movebank CSV schema (from the published "Long term study on migratory
# movement of Alpine swifts" series, Meier et al. 2020):
#   columns: timestamp, location-long, location-lat,
#            individual-local-identifier, tag-local-identifier,
#            sensor-type, study-name, ... (R replaces "-" with ".")
# References:
#   Movebank Data Repository: https://datarepository.movebank.org
#   Meier C.M. et al. 2020. J Avian Biol 51:e02515. doi:10.1111/jav.02515
# =============================================================================

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(lubridate)
})

# Mapping from Movebank study name prefix -> colony metadata.
# Matches the colonies.csv shipped in data/raw/.
STUDY_TO_COLONY <- list(
  "Switzerland Baden"      = list(colony_id = "CH_BAD", colony_name = "Baden",      country = "Switzerland", flyway = "western"),
  "Switzerland Biel"       = list(colony_id = "CH_BIE", colony_name = "Biel",       country = "Switzerland", flyway = "western"),
  "Switzerland Lausanne"   = list(colony_id = "CH_LAU", colony_name = "Lausanne",   country = "Switzerland", flyway = "western"),
  "Switzerland Lenzburg"   = list(colony_id = "CH_LEN", colony_name = "Lenzburg",   country = "Switzerland", flyway = "western"),
  "Switzerland Solothurn"  = list(colony_id = "CH_SOL", colony_name = "Solothurn",  country = "Switzerland", flyway = "western"),
  "Switzerland Luzern"     = list(colony_id = "CH_LUZ", colony_name = "Luzern",     country = "Switzerland", flyway = "western"),
  "Spain Tarragona"        = list(colony_id = "ES_TAR", colony_name = "Tarragona",  country = "Spain",       flyway = "western"),
  "Bulgaria Sofia"         = list(colony_id = "BG_SOF", colony_name = "Sofia",      country = "Bulgaria",    flyway = "eastern"),
  "Turkey"                 = list(colony_id = "TR_PIR", colony_name = "Pirasali",   country = "Turkey",      flyway = "eastern")
)

#' Standardise the column names of a Movebank-style data frame.
#' Different CSV writers preserve or transform hyphens differently
#' (readr keeps `location-lat`, base read.csv produces `location.lat`,
#' the `move` package produces `location_lat` or `coords.x1`...).
#' We therefore match each target name against a list of case-insensitive
#' regex patterns and pick the first column that matches.
.normalise_movebank_cols <- function(df) {
  rename_if <- function(d, new_name, patterns) {
    for (pat in patterns) {
      hit <- grep(pat, names(d), ignore.case = TRUE, value = TRUE,
                  perl = TRUE)
      if (length(hit) > 0) {
        names(d)[names(d) == hit[1]] <- new_name
        return(d)
      }
    }
    d
  }
  df |>
    rename_if("timestamp",
              c("^timestamps?$", "^time$")) |>
    rename_if("lon",
              c("^location[ ._-]?long(itude)?$", "^longitude$",
                "^lon$", "^coords\\.x1$")) |>
    rename_if("lat",
              c("^location[ ._-]?lat(itude)?$", "^latitude$",
                "^lat$", "^coords\\.x2$")) |>
    rename_if("bird_id",
              c("^individual[ ._-]local[ ._-]identifier$",
                "^trackId$", "^individualID$", "^bird_id$"))
}

#' Look at a Movebank CSV's `study.name` (or filename) and attach colony info.
.attach_colony_metadata <- function(df, file_path) {
  study_col <- intersect(c("study.name", "study_name"), names(df))
  if (length(study_col) > 0) {
    sn <- df[[study_col[1]]][1]
  } else {
    # Fall back to filename detection
    sn <- basename(file_path)
  }
  hit <- NULL
  for (key in names(STUDY_TO_COLONY)) {
    if (grepl(key, sn, ignore.case = TRUE, fixed = FALSE)) {
      hit <- STUDY_TO_COLONY[[key]]; break
    }
  }
  if (is.null(hit)) {
    warning("Could not identify colony for file ", basename(file_path),
            " - skipping.")
    return(NULL)
  }
  df |> dplyr::mutate(
    colony_id   = hit$colony_id,
    colony_name = hit$colony_name,
    country     = hit$country,
    flyway      = hit$flyway
  )
}

#' Scan data/raw/movebank/ for *-tracks.csv files and read them.
load_movebank_local <- function(dir = file.path("data", "raw", "movebank")) {
  if (!dir.exists(dir)) return(NULL)
  files <- list.files(dir, pattern = "tracks.*\\.csv$",
                      full.names = TRUE, ignore.case = TRUE)
  if (length(files) == 0) return(NULL)

  message("Found ", length(files), " Movebank tracks file(s) in ", dir)
  dfs <- lapply(files, function(f) {
    message("  - reading ", basename(f))
    raw <- tryCatch(
      readr::read_csv(f, show_col_types = FALSE, progress = FALSE),
      error = function(e) {
        message("    failed: ", conditionMessage(e)); NULL
      })
    if (is.null(raw)) return(NULL)
    raw <- .normalise_movebank_cols(raw)
    # Quick diagnostic: confirm we found lat/lon
    if (!all(c("lat", "lon") %in% names(raw))) {
      message("    ! lat/lon not detected. Columns present: ",
              paste(head(names(raw), 15), collapse = ", "), " ...")
      return(NULL)
    }
    raw <- .attach_colony_metadata(raw, f)
    raw
  })
  dfs <- Filter(Negate(is.null), dfs)
  if (length(dfs) == 0) return(NULL)

  combined <- dplyr::bind_rows(dfs)

  # Ensure a `comments` column exists - data_processing.R's phase
  # classifier reads it (Movebank's own state labels: "breeding site",
  # "non-breeding site", "migration").
  if (!"comments" %in% names(combined)) {
    combined$comments <- NA_character_
  }

  # Keep only the columns the dashboard needs (comments included)
  combined <- combined |>
    dplyr::filter(!is.na(.data$lat), !is.na(.data$lon)) |>
    dplyr::mutate(
      timestamp = as.POSIXct(timestamp, tz = "UTC"),
      year      = lubridate::year(timestamp),
      doy       = lubridate::yday(timestamp),
      phase     = NA_character_   # will be derived in processing step
    ) |>
    dplyr::select(timestamp, bird_id, colony_id, colony_name, country,
                  flyway, year, doy, lat, lon, phase, comments)

  message("Loaded ", nrow(combined), " rows across ",
          length(unique(combined$bird_id)), " birds and ",
          length(unique(combined$colony_id)), " colonies.")
  combined
}

#' Public entry point. Returns list(tracks, reference, colonies, source).
load_tracking_data <- function(prefer_movebank = TRUE) {
  raw_dir <- file.path("data", "raw")
  colonies <- readr::read_csv(file.path(raw_dir, "colonies.csv"),
                              show_col_types = FALSE)
  reference <- readr::read_csv(file.path(raw_dir, "reference.csv"),
                               show_col_types = FALSE)

  if (prefer_movebank) {
    mb <- tryCatch(load_movebank_local(),
                   error = function(e) {
                     message("Movebank local load failed: ",
                             conditionMessage(e)); NULL
                   })
    if (!is.null(mb) && nrow(mb) > 0) {
      message("Using REAL Movebank Data Repository tracks.")
      return(list(tracks = mb, reference = reference,
                  colonies = colonies, source = "movebank-local"))
    }
  }

  message("Using bundled synthetic tracks (calibrated to Meier et al. 2020).")
  tracks <- readr::read_csv(file.path(raw_dir, "tracks.csv"),
                            show_col_types = FALSE)
  # Synthetic tracks carry a `phase` column but no Movebank-style
  # `comments`. Reverse-map phase -> comments so data_processing.R's
  # comments-based classifier returns identical results.
  if (!"comments" %in% names(tracks)) {
    tracks$comments <- dplyr::case_when(
      tracks$phase == "breeding"  ~ "breeding site",
      tracks$phase == "wintering" ~ "non-breeding site",
      tracks$phase == "migration" ~ "migration",
      TRUE                         ~ NA_character_
    )
  }
  list(tracks = tracks, reference = reference, colonies = colonies,
       source = "synthetic")
}
