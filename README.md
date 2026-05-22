# Alpine Swift Migration Dashboard

Interactive R Shiny dashboard visualising the trans-Saharan migration of
Alpine swifts (*Tachymarptis melba*) tracked with light-level geolocators
across four breeding populations (Switzerland, Spain, Bulgaria, Turkey).

Built for **CCES – Communication and Collaboration in Environmental Science**
(ZHAW, FS 2026).

## Quick start

```r
# 1. First time only – install packages & build processed data
source("_setup.R")

# 2. Launch the dashboard
shiny::runApp()
```

R ≥ 4.3 is required.  The project is fully portable: every path is
relative.  Open it as a Positron / RStudio project to take advantage of
the working-directory convention.

## Project layout

```
Alpine Swift Dashboard/
├── app.R                       # entry point
├── _setup.R                    # one-time bootstrap
├── R/                          # modular Shiny code
│   ├── data_acquisition.R      # Movebank ↔ synthetic loader
│   ├── data_processing.R       # cleaning, derived metrics
│   ├── helpers.R               # palettes, basemap config
│   ├── mod_filters.R           # sidebar filters module
│   ├── mod_map.R               # leaflet map module
│   ├── mod_phenology.R         # latitude×DOY + stay×lat plots
│   ├── mod_metrics.R           # KPI value boxes
│   └── mod_animation.R         # Phase-2 animation module
├── data/
│   ├── raw/                    # tracks.csv, reference.csv, colonies.csv
│   └── processed/              # cached RDS after first run
├── www/
│   └── custom.css              # subdued scientific theme
├── reports/
│   ├── technical_report.qmd    # Quarto computational notebook
│   └── about.md
└── README.md
```

## Data

The repository ships with a **synthetic, scientifically calibrated**
dataset of 215 individuals across 9 colonies, generated to match the
findings of Meier et al. (2020):

- 110 Swiss birds (6 colonies) – western flyway
- 17 Spanish birds (Tarragona) – western flyway
- 27 Bulgarian birds (Sofia) – eastern flyway
- 61 Turkish birds (Pırasalı) – eastern flyway
- All wintering 5–10 °N in West / Central Africa
- Migration duration: median ~6 days autumn, ~9 days spring
- Light-level geolocator positional uncertainty modelled (~150 km,
  larger near equinoxes)

To swap in **real** Movebank data, edit `R/data_acquisition.R` and set
`prefer_movebank = TRUE`.  You will need the `move` R package and a
Movebank account with access to the published study series.

## Phase-2 extension: animation

The dashboard implements **animated migration over time** as its Phase-2
extension. A day-of-year slider with configurable trail length and frame
rate replays the annual cycle, making the divergence between the western
and eastern Saharan flyways visually obvious.

## Reference

Meier C.M., Karaardıç H., Aymí R., Peev S.G., Witvliet W. & Liechti F. 2020.
Population-specific adjustment of the annual cycle in a super-swift
trans-Saharan migrant. *Journal of Avian Biology* 51: e02515.
[doi:10.1111/jav.02515](https://doi.org/10.1111/jav.02515)
