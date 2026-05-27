# Alpine Swift Migration Dashboard

An interactive R Shiny dashboard that visualises the trans-Saharan migration
of the Alpine Swift (*Tachymarptis melba*, formerly *Apus melba*). Built for
the CCES module (FS 2026) at ZHAW Environmental Science, based on
[Meier et al. 2020](https://doi.org/10.1111/jav.02515).

## Quick start

```r
# 1) Install all dependencies (run once after cloning)
source("_setup.R")

# 2) Optionally drop real Movebank CSVs into data/raw/movebank/
#    (otherwise the dashboard runs on the bundled synthetic dataset)
#    See reports/DOWNLOAD_MOVEBANK_DATA.md for step-by-step instructions.

# 3) Launch
shiny::runApp()
```

A green / amber banner in the sidebar tells you whether the dashboard is
running on real Movebank Data Repository data or on the synthetic fallback.



## Project layout

```
.
+- app.R                       # Shiny entry point
+- _setup.R                    # dependency installer
+- R/
|  +- helpers.R                # palettes, basemap config, legend helpers
|  +- data_acquisition.R       # Movebank CSV ingestion / synthetic fallback
|  +- data_processing.R        # cleaning, airspeed filter, daily aggregation
|  +- mod_filters.R            # sidebar filter module
|  +- mod_metrics.R            # KPI value boxes
|  +- mod_animation.R          # merged map + animation + click-to-highlight
|  +- mod_phenology.R          # latitude-by-doy plot
+- data/raw/                   # synthetic + real Movebank CSVs 
+- data/processed/             # tracks_processed.rds cache
+- reports/
|  +- about.md                 # rendered into the dashboard's About tab
|  +- DOWNLOAD_MOVEBANK_DATA.md
|  +- technical_report.qmd     # full academic write-up
|  +- references.bib
+- www/custom.css              # dashboard styling
```

## Reference

Meier C.M., Karaardic H., Aymi R., Peev S.G., Witvliet W. & Liechti F.
(2020). Population-specific adjustment of the annual cycle in a
super-swift trans-Saharan migrant. *Journal of Avian Biology* 51:
e02515. doi:[10.1111/jav.02515](https://doi.org/10.1111/jav.02515)
