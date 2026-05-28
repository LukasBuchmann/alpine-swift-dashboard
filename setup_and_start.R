# 1) Install all dependencies (run once after cloning)
source("_setup.R")

# 2) Optionally drop real Movebank CSVs into data/raw/movebank/
#    (otherwise the dashboard runs on the bundled synthetic dataset)
#    See reports/DOWNLOAD_MOVEBANK_DATA.md for step-by-step instructions.

# 3) Launch
shiny::runApp()

