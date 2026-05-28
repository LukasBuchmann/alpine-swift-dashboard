# Alpine Swift Migration Dashboard

An interactive R Shiny dashboard that visualises the trans-Saharan migration of the Alpine Swift (Tachymarptis melba, formerly Apus melba).

## Quick start

To run the dashboard locally, follow these steps in order:

### 1) Set up the environment

First, install and activate the required dependencies using the provided Conda environment file:

Linux:
```bash
conda env create -f environment.yml
conda activate alpine-swift
```

Windows:
```bash
conda env create -f win_env_01.yml
conda activate alpine-swift
```

### 2) Run the application

After the environment is ready, start the Shiny app from R:

```r
source("app.R")
```

## Project layout

```
.
+- app.R                       # Shiny entry point
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
|  +- technical_report_2.qmd   # full academic write-up
|  +- references.bib
+- www/custom.css              # dashboard styling
```

## Reference

Meier C.M., Karaardic H., Aymi R., Peev S.G., Witvliet W. & Liechti F.
(2020). Population-specific adjustment of the annual cycle in a
super-swift trans-Saharan migrant. *Journal of Avian Biology* 51:
e02515. doi:[10.1111/jav.02515](https://doi.org/10.1111/jav.02515)
