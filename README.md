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

## What you see

* A single integrated map showing every retained fix as a translucent
  Path-Resamples dot cloud (Meier 2020, Figure 1 style). The current day
  is drawn on top of everything else, slightly translucent.
* A togglable Migration-Uncertainty shadow at every migration fix - a thin
  vertical bar from the 10th to the 90th rolling-window latitude percentile
  for that bird, so the well-known geolocator latitudinal error is shown
  explicitly rather than hidden under a hard line.
* A togglable Moving-point Trail (sperm trail) over the last 7 / 14 / 365
  days ending on the current day-of-year.
* Click any dot to highlight that bird's full bird-year track; click again
  to deselect. The sidebar card shows colony, country, flyway, fix count,
  latitude range, and observed phases.
* Below the map: a latitude-by-population boxplot of the current day's
  active individuals, and (in a separate card) the classical latitude
  by day-of-year phenology plot - lines are split where the tracker had
  no fix for more than 14 days, so we never draw fake interpolation
  across multi-week gaps.

## Cartographic principles (Slocum et al. 2009)

* **Figure / ground.** Pale CartoDB Positron basemap - thematic symbols
  dominate without heavy stroke weights.
* **Qualitative colour.** ColorBrewer Dark2 (Okabe-Ito-derived,
  colour-blind safe) for nominal `country`, `colony`, and `flyway`
  groupings. The two flyway colours are exactly the first two Dark2
  hues, so the palette is internally consistent whether you group by
  country or by flyway.
* **Sequential colour.** ColorBrewer YlGnBu 3-step for the ordinal
  `year` channel (2014 -> 2016). Never spectral / rainbow.
* **Visual variables follow measurement level.** Nominal categories
  encoded by *hue*; ordinal years by *lightness*; ratio uncertainty by
  *length* (lat_lo -> lat_hi shadow stroke); animation time by *position
  in time*. (See `reports/technical_report.qmd` for the full table.)
* **Map projection.** Leaflet renders Web Mercator interactively, but the
  static figures in the technical report are reprojected to Eckert IV
  (EPSG:54012) so areas across the Europe-Africa extent are faithful.

## Uncertainty visualisation

Light-level geolocators carry an inherent latitudinal error of about
150 km that can balloon to ~300 km near the equinoxes. The dashboard
makes that uncertainty visible rather than hiding it:

1. The 7-day rolling 10/90 percentile latitude band is drawn as the
   "Migration uncertainty" layer on the map.
2. The path-resample dot cloud uses low alpha so that overlapping fixes
   show as denser regions - density itself becomes a credibility cue.
3. Lines in the phenology plot are split where the tracker missed more
   than 14 days. No fake interpolation crosses those gaps.

## Project layout

```
.
+- app.R                       # Shiny entry point
+- _setup.R                    # one-shot dependency installer
+- R/
|  +- helpers.R                # palettes, basemap config, legend helpers
|  +- data_acquisition.R       # Movebank CSV ingestion / synthetic fallback
|  +- data_processing.R        # cleaning, airspeed filter, daily aggregation
|  +- mod_filters.R            # sidebar filter module
|  +- mod_metrics.R            # KPI value boxes
|  +- mod_animation.R          # merged map + animation + click-to-highlight
|  +- mod_phenology.R          # latitude-by-doy plot
+- data/raw/                   # synthetic + real Movebank CSVs go here
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
