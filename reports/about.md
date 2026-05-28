## Alpine Swift Migration Dashboard

This dashboard visualises the trans-Saharan migration of the Alpine Swift
(*Tachymarptis melba*, formerly *Apus melba*) - one of the fastest non-stop
long-distance migrants known. Light-level geolocator tracks come from nine
populations across four countries along a 12-degree latitudinal gradient across the western
Palaearctic.

### Scope

- **Spatial extent.** Europe, the Sahara, West and Central Africa
  (~18 deg W to 45 deg E, ~5 deg N to 55 deg N).
- **Temporal extent.** 2014 - 2017 annual cycles.
- **Populations.** Switzerland (Baden, Biel, Lausanne, Lenzburg, Luzern,
  Solothurn - western flyway), Spain (Tarragona - western), Bulgaria
  (Sofia - eastern), Turkey (Pirasali Island - eastern).
- **One integrated map** combining the always-visible Path-Resamples
  dot cloud with a server-driven day-of-year animation. Press Play to
  animate; press Reset to return to day 100.

### Map layers (toggle in the top-right control)

- **Path resamples.** Every retained daily fix in the current filter
  selection, drawn at low alpha. Migration fixes are slightly brighter
  (alpha 0.55) than breeding / wintering fixes (alpha 0.28), so the
  diffuse trans-Saharan corridor is visible without saturating the
  breeding clusters.
- **Migration uncertainty.** A thin vertical shadow at every migration
  fix, running from the 7-day rolling 10th-percentile latitude to the
  90th-percentile latitude. Visualises the well-known geolocator
  latitudinal error rather than hiding it under a single hard line.
- **Moving trail (sperm trail).** Optional smaller dots connected by
  a line, showing each bird's last 1 / 3 / 7 daily fixes.
- **Current day.** Brighter, slightly translucent markers for every bird
  active on the current animation day. Always rendered on top.
- **Selected bird.** Click any dot to draw its full bird-year tracks in
  black with yellow waypoints. Click the same bird again to deselect.

### Animation

- **Play / Pause** toggles a 200 ms server tick.
- **Reset** returns to day 100 and clears any selection.
- **Speed.** Slow (1 d / tick), Medium (3 d / tick), Fast (7 d / tick).
- **Moving-point trail.** Off, 1 day, 3 days, or 7 days of small
  dots connected by a line.
- **Date readout** above the slider keeps the viewer oriented.

### Data pipeline

- **Source.** Movebank Data Repository CSVs in `data/raw/movebank/` when
  present, otherwise a scientifically calibrated synthetic dataset.
- **Airspeed filter.** Fixes that would require more than 50 km/h ground
  speed since the previous fix are dropped (Meier 2020 cruising speed
  ~12.6 m/s = 45.4 km/h, plus a safety margin).
- **Daily aggregation.** Per bird and date, the median lat / lon of all
  twilight fixes. Annual-cycle phase (`breeding` / `migration` /
  `wintering`) is taken from Movebank's `comments` column.
- **Uncertainty band.** Per bird and year, a 7-day centred rolling
  window of the 10 / 90 percentile latitude gives `lat_lo` and `lat_hi`.

### Cartographic design (after Slocum et al. 2009, MacEachren 1995,
### Cairo 2016)

- **Figure / ground.** Subdued CartoDB Positron basemap; thematic
  symbols dominate.
- **Qualitative colour.** ColorBrewer Dark2 for nominal grouping
  variables (country, colony, flyway). Colour-blind safe; the two
  flyways reuse the first two Dark2 hues so the palette is consistent
  whether you group by country or by flyway.
- **Sequential colour.** ColorBrewer YlGnBu 3-step for the ordinal Year
  channel (2014 -> 2016).
- **Visual variables follow measurement level.** Hue encodes nominal
  category; lightness encodes ordinal year; length encodes ratio
  uncertainty (lat_lo to lat_hi); position in time encodes the animation
  cycle. (See the full technical report for the rationale.)
- **Animation orientation.** Large date readout, scrub slider, Play /
  Reset, configurable speed, and a toggleable moving-point trail give
  the viewer complete temporal control.

### Reference

Meier C.M., Karaardic H., Aymi R., Peev S.G., Witvliet W. & Liechti F.
(2020). Population-specific adjustment of the annual cycle in a
super-swift trans-Saharan migrant. *Journal of Avian Biology* 51:
e02515. doi:[10.1111/jav.02515](https://doi.org/10.1111/jav.02515)
