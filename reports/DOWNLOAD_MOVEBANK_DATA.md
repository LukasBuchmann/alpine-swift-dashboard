# How to load real Movebank data

The dashboard auto-detects real Movebank CSVs in `data/raw/movebank/`.
When that folder is empty (or missing), it transparently falls back to
the bundled synthetic dataset. **No code changes are required to swap
between the two sources** — the sidebar's "Data source" banner shows
which is active.

## What's openly available vs. not

| Population | Colony | MDR public? | How to get it |
|------------|--------|-------------|---------------|
| Switzerland (W flyway) | Baden | yes | direct download |
| Switzerland (W flyway) | Biel | yes | direct download |
| Switzerland (W flyway) | Lausanne | yes | direct download |
| Switzerland (W flyway) | Lenzburg | yes | direct download |
| Switzerland (W flyway) | Solothurn | yes | direct download |
| Switzerland (W flyway) | Luzern | not on MDR | Movebank account + permission |
| Spain (W flyway) | Tarragona | yes | direct download |
| Bulgaria (E flyway) | Sofia | not on MDR | Movebank account + permission |
| Turkey (E flyway) | Pırasalı | not on MDR | Movebank account + permission |

The six MDR-public colonies cover ~127 of the 215 birds in Meier et al.
2020 and include the entire western flyway. With those alone the
latitudinal gradient is fully represented (Spain 41 °N → Switzerland
46–47 °N). For the eastern flyway, the synthetic fallback fills in
until you have access.

## Easiest path: manual download

### Step 1 — open each dataset page

| Colony | URL |
|--------|-----|
| Switzerland Baden | <https://datarepository.movebank.org/handle/10255/move.1172> |
| Switzerland Biel | <https://datarepository.movebank.org/handle/10255/move.1190> |
| Switzerland Lausanne | <https://datarepository.movebank.org/handle/10255/move.1202> |
| Switzerland Lenzburg | <https://datarepository.movebank.org/handle/10255/move.1178> |
| Switzerland Solothurn | <https://datarepository.movebank.org/items/ec6d76ef-fa51-4cc7-9258-34bbbff8a5b9> |
| Spain Tarragona | <https://datarepository.movebank.org/entities/datapackage/031581a9-35e6-4096-9b87-8b6c7711661c/full> |

### Step 2 — accept the licence

Each page has a Creative Commons licence notice and a download button.
Click through and download **only the `tracks.csv` file** for each
colony — that's the one the dashboard reads.

Skip these (huge and not needed):
- `light-levels.csv` (50–350 MB raw light readings)
- `twilights.csv` (intermediate Hill–Ekström output)
- `barometer.csv` (only on a few colonies)

You do **not** need a Movebank account for these MDR-public datasets;
clicking through the Creative Commons licence on the dataset page is
enough.

### Step 3 — place the files

Create the folder `data/raw/movebank/` and drop the CSVs in. The loader
identifies the colony from either the file's `study-name` column or its
filename, so the suggested naming pattern is:

```
data/raw/movebank/
├── Switzerland_Baden-tracks.csv
├── Switzerland_Biel-tracks.csv
├── Switzerland_Lausanne-tracks.csv
├── Switzerland_Lenzburg-tracks.csv
├── Switzerland_Solothurn-tracks.csv
└── Spain_Tarragona-tracks.csv
```

Underscore vs. space doesn't matter; matching is case-insensitive
substring against `Switzerland Baden`, `Spain Tarragona`, etc.

### Step 4 — rebuild the cache and launch

```r
unlink("data/processed/tracks_processed.rds")   # invalidate cache
source("R/data_acquisition.R")
source("R/data_processing.R")
build_processed_data(force = TRUE)               # rebuild with new CSVs
shiny::runApp()
```

The first rebuild after adding new files takes ~15–30 s. It computes the
airspeed-filtered daily medians and the per-bird latitudinal-uncertainty
band (`lat_lo` / `lat_hi`) used to render the migration shadow on the
animated map. The sidebar's "Data source" banner should switch from
amber ("Synthetic") to green ("Real Movebank Data Repository — *N*
colonies, *M* birds").

## Alternative: live Movebank API (for the missing colonies)

To add Luzern (CH), Sofia (BG), or Pırasalı (TR) you need a free
Movebank account at <https://www.movebank.org/> and per-study download
permission from the Swiss Ornithological Institute (usually granted
to academic requests within a few days). Once approved you can use the
`move2` package (the modern sf-compatible successor to `move`) to pull
the study directly, then write the same `tracks.csv` shape this
dashboard expects:

```r
# install.packages("move2")  # not required by the dashboard itself
library(move2)
movebank_store_credentials(username = "your_user")
mv <- movebank_download_study(
  study_id   = movebank_get_study_id("Sofia - Long term study..."),
  attributes = c("timestamp", "location_long", "location_lat",
                 "individual_local_identifier", "comments"))
readr::write_csv(as.data.frame(mv),
                 "data/raw/movebank/Bulgaria_Sofia-tracks.csv")
```

Then repeat **Step 4** to rebuild the cache. `move2` is *not* listed in
`_setup.R` because it is only needed for this optional ingestion path;
install it on demand.

## Recommendation

For an academic deliverable, the six MDR-public colonies are
sufficient — the western flyway is fully populated, the latitudinal
gradient is intact, and the eastern-flyway synthetic backfill is
clearly documented in the report. Add the live-API colonies only if
you receive access in time.
