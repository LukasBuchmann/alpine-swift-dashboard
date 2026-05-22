# Alpine Swift Migration Dashboard

Interactive R Shiny dashboard visualising the trans-Saharan migration of
Alpine swifts (*Tachymarptis melba*) tracked with light-level geolocators
across four breeding populations (Switzerland, Spain, Bulgaria, Turkey).

Built for **CCES – Communication and Collaboration in Environmental Science**
(ZHAW, FS 2026).

## Quick start

```r
# 1. First time only — install packages + build the processed cache
source("_setup.R")

# 2. Launch the dashboard
shiny::runApp()
```

R ≥ 4.3 is required. The project is fully portable: every path is
relative. Open it as a Positron / RStudio project to take advantage of
the working-directory convention.

A first-time launch on real Movebank data spends ~30–60 s pre-computing
the burst-aware hourly interpolation table. Subsequent launches read
the cached `data/processed/tracks_processed.rds` and start in seconds.

## Project layout

```
Alpine Swift Dashboard/
├── app.R                       # entry point (single page + About)
├── _setup.R                    # one-time bootstrap
├── R/                          # modular Shiny code
│   ├── data_acquisition.R      # Movebank ↔ synthetic loader
│   ├── data_processing.R       # cleaning + burst-aware hourly interp.
│   ├── helpers.R               # palettes, basemap, shared utilities
│   ├── mod_filters.R           # sidebar filters module
│   ├── mod_phenology.R         # latitude × day-of-year plot
│   ├── mod_metrics.R           # KPI value boxes (3)
│   └── mod_animation.R         # merged static + animated map module
├── data/
│   ├── raw/                    # tracks.csv, reference.csv, colonies.csv
│   │   └── movebank/           # (optional) real Movebank CSVs
│   └── processed/              # cached RDS after first run
├── www/
│   └── custom.css              # subdued scientific theme
├── reports/
│   ├── technical_report.qmd    # Quarto computational notebook
│   ├── about.md                # in-app About page
│   ├── DOWNLOAD_MOVEBANK_DATA.md
│   └── references.bib
└── README.md
```

## Data sources

The loader checks `data/raw/movebank/` for real Movebank
Data Repository CSVs and uses them when present. Otherwise it falls
back to a scientifically-calibrated synthetic dataset bundled in
`data/raw/`. The sidebar's "Data source" banner shows which is active.

To install real Movebank data, see `reports/DOWNLOAD_MOVEBANK_DATA.md`.

The synthetic fallback reproduces the empirical properties of the
Meier et al. 2020 study (215 birds, four populations, two flyways,
5–10 °N wintering, median 6 / 9-day migrations, ~150 km geolocator
uncertainty enlarged near equinoxes).

## Dashboard features

- **One integrated map** combining the static spatial overview and the
  animated migration. Press **Play** to animate; press **Reset** to
  return to the static overview.
- **Layer toggles** (top-right of the map): Tracking points · Colony
  residence · Tropic of Cancer.
- **Click popups** on every tracking point and colony marker.
- **Animation controls**: Play / Pause / Reset, scrub slider (1-365 d,
  0.5 d step), Speed (Slow / Medium / Fast), Sperm trail (Off / 12 h /
  24 h / 72 h with connecting polyline).
- **Color by**: Country / Colony / Flyway / Year — recolours every
  view in lockstep without changing which points are displayed.
- **Quick-filter buttons**: All / W flyway / E flyway / Clear.
- **Phenology plot** (latitude × day-of-year, gap-broken at >14 d).
- **KPIs**: Individuals tracked · Daily fixes · Populations / colonies.

## Scientific notes

- **Phase classification** (breeding / migration / wintering) is read
  verbatim from the Movebank `comments` column — the Meier et al. 2020
  authors' own labels — never a heuristic.
- **Burst-aware hourly interpolation**: linear interpolation between
  consecutive daily medians is applied **only within tracking bursts**
  (gaps ≤ 14 days). Multi-week tag dropouts stay visibly empty rather
  than being bridged by straight lines that would imply movement we
  cannot observe.
- **Cartographic compliance**: ColorBrewer "Dark2" for nominal data
  (country / colony / flyway), "YlGnBu" 3-step sequential for the
  ordinal Year channel, area-proportional colony markers (Slocum
  ch. 14), Positron pale-grey figure-ground basemap, configurable
  playback pacing (Slocum ch. 22).

## Reference

Meier C.M., Karaardıç H., Aymí R., Peev S.G., Witvliet W. & Liechti F. 2020.
Population-specific adjustment of the annual cycle in a super-swift
trans-Saharan migrant. *Journal of Avian Biology* 51: e02515.
[doi:10.1111/jav.02515](https://doi.org/10.1111/jav.02515)
