## Alpine Swift Migration Dashboard

This dashboard visualises the trans-Saharan migration of the Alpine Swift
(*Tachymarptis melba*, formerly *Apus melba*) — one of the fastest non-stop
long-distance migrants known. Light-level geolocator tracks come from four
populations along a 12-degree latitudinal gradient across the western
Palaearctic.

### Dashboard scope

- **Spatial extent.** Europe, the Sahara, West and Central Africa
  (~18 °W to 45 °E, ~5 °N to 55 °N).
- **Temporal extent.** 2014–2016 annual cycles.
- **Populations.** Switzerland (Baden, Biel, Lausanne, Lenzburg, Luzern,
  Solothurn — western flyway), Spain (Tarragona — western), Bulgaria
  (Sofia — eastern), Turkey (Pırasalı Island — eastern).
- **One integrated map** combining the static spatial overview and the
  animated migration. Press Play to animate; press Reset to return to
  the static view.

### Map features

- **Tracking points** (toggleable in the top-right layer control): the
  hourly-interpolated daily fixes, colour-coded by Country / Colony /
  Flyway / Year (sidebar selector).
- **Density** (toggleable, off by default): viridis-coloured kernel
  density of migration-phase positions — the trans-Saharan corridors.
- **Colony residence** (toggleable): breeding-colony markers scaled by
  number of birds tracked. Click for details.
- **Tropic of Cancer** (toggleable): dashed reference line at 23.4366 °N.
- **Click popups** on every tracking point and colony marker.

### Animation

- **Play / Pause**: starts and stops a client-side animation loop. Pause
  is instant (no server round-trip).
- **Reset**: returns the map to the static-overview state — all points
  clearly visible, no highlight layer.
- **Scrub slider**: jumps to any day of the year; advances by 12-hour
  steps for fine control.
- **Speed**: 5 / 15 / 40 days per real-time second.
- **Sperm trail**: Off / 12 h / 24 h / 72 h of trailing positions per
  bird, drawn as smaller faded dots connected by a polyline to the
  current bright position.

### Data pipeline

The dashboard reads daily-resolution geolocator fixes from the Movebank
Data Repository and computes two derived tables:

1. **Daily medians.** Per bird per calendar day, the median of all
   twilight fixes. Drives the phenology summaries.
2. **Burst-aware hourly interpolation.** Per `(bird, year, burst)`,
   positions are linearly interpolated to hourly resolution using
   `zoo::na.approx`. A *burst* is a continuous tracking segment with no
   gap longer than 14 days. **Interpolation never spans a burst
   boundary** — a multi-week gap (tag malfunction, equinox blackout)
   stays as a gap because we have no information about the bird's
   position during it. Within a burst, linear interpolation is the
   standard practice for light-level geolocator data: the daily
   positional uncertainty (~150 km nominal, ~300 km near equinoxes;
   Lisovski & Hahn 2012, Lisovski et al. 2020) is larger than any
   sub-daily trajectory curvature a smoother could introduce.

Annual-cycle phase (breeding / migration / wintering) is taken verbatim
from the dataset's `comments` column — the original authors' own
classification.

### Animation architecture

Pure client-side. The Shiny server pre-computes the hourly stream once
per filter change, subsamples it to four fixes per day per
`(bird, year)` deployment, and ships the compact payload to the browser
via a custom message. All animation timing, slider control, and per-
frame canvas rendering run in `requestAnimationFrame` — zero per-frame
WebSocket round-trips, instant pause, no playback-lag-after-stop. The
current day-of-year is debounced back to R only to drive the vertical
"you are here" marker on the two context plots beneath the map.

### Cartographic design notes (after Slocum et al., 2009)

- **Figure / ground.** Subdued CartoDB Positron basemap; thematic
  symbols dominate.
- **Qualitative colour.** Okabe-Ito-derived, colour-blind-safe palette
  for the nominal "Color by" variables (Country, Colony, Flyway).
- **Sequential colour for the Year channel.** Years are ordinal, so a
  viridis 3-step (`#440154` → `#21918C` → `#FDE725`) encodes 2014 → 2016
  as a perceptually uniform progression.
- **Symbolisation.** Tracking points use a constant small size with low
  fill-alpha in animation mode and a larger / brighter rendering in
  overview mode; colony markers scale with √(n birds) — symbol *area*
  encodes quantity (Slocum ch. 14).
- **Tropic of Cancer.** Drawn as a dashed reference line — every Alpine
  swift in the dataset crosses it twice a year.
- **Animation orientation.** A large date readout, scrub slider, Reset
  button, and configurable playback speed give the viewer complete
  temporal control (Slocum ch. 22; Tversky 2002).

### Reference

Meier C.M., Karaardıç H., Aymí R., Peev S.G., Witvliet W. & Liechti F.
(2020). Population-specific adjustment of the annual cycle in a
super-swift trans-Saharan migrant. *Journal of Avian Biology* 51: e02515.
doi:[10.1111/jav.02515](https://doi.org/10.1111/jav.02515)
