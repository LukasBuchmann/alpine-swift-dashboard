# =============================================================================
# _setup.R - Project bootstrap
# Run once after cloning the project: source("_setup.R")
# =============================================================================
# Installs all packages required by the Alpine Swift Dashboard.
# Compatible with Positron / RStudio. Standard R >= 4.3 expected.

# Ensure the working directory is the project root (where this script lives).
# This is necessary because all paths in the project are relative.
#
# Detection strategy: walk every active call frame looking for `ofile`
# (set by source()), then fall back to `--file=` from Rscript invocation.
.locate_this_file <- function() {
  frames <- sys.frames()
  for (i in rev(seq_along(frames))) {
    of <- frames[[i]]$ofile
    if (!is.null(of) && nzchar(of)) return(of)
  }
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) return(sub("^--file=", "", file_arg[1]))
  NULL
}

.this <- tryCatch(.locate_this_file(), error = function(e) NULL)
if (!is.null(.this)) {
  proj_root <- dirname(normalizePath(.this, winslash = "/", mustWork = FALSE))
  setwd(proj_root)
  message("Working directory set to: ", proj_root)
} else {
  message("Could not auto-detect the script location. ",
          "Please run setwd() manually to the project root before continuing.")
}

required_pkgs <- c(
  # Core
  "shiny", "bslib", "bsicons", "shinyWidgets", "markdown",
  
  # Data wrangling
  "dplyr", "tidyr", "readr", "lubridate", "purrr", 
  "zoo",    # <--- ADDED: Required for hourly na.approx() interpolation
  
  # Spatial
  "sf", "leaflet", "leaflet.extras", "geosphere",
  
  # Visualisation
  "ggplot2", "plotly", "scales", "viridisLite", "RColorBrewer",
  
  # API / Movebank Data
  "move2",  # <--- UPDATED: 'move2' is the modern, sf-compatible standard
  "httr2"   # <--- ADDED: Useful for handling Movebank REST API requests/credentials
)

installed <- rownames(installed.packages())
to_install <- setdiff(required_pkgs, installed)

if (length(to_install) > 0) {
  message("Installing: ", paste(to_install, collapse = ", "))
  install.packages(to_install, repos = "https://cloud.r-project.org")
} else {
  message("All packages already installed.")
}

# Build processed data on first run
message("Pre-processing tracking data...")
source("R/data_acquisition.R")
source("R/data_processing.R")
build_processed_data()
message("Setup complete. Run the dashboard with: shiny::runApp()")