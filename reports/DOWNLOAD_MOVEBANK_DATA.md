# How to load real Movebank data

This dashboard uses synthetic tracks by default so it runs immediately.
To swap in **real** geolocator data from the published Movebank Data
Repository (MDR), follow the steps below — no R code changes required.

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

The **six MDR-public colonies cover ~127 of the 215 birds in Meier et al.
2020** and include the entire western flyway. The dashboard's storytelling
is already complete with these — the latitudinal gradient is fully
represented (Spain 41 °N, Switzerland 46–47 °N). For the eastern flyway,
the synthetic fallback fills in until permission is granted.

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

Each page has a Creative Commons licence notice and a "Download dataset"
button (or per-file download links). Click through and download **only
the `tracks.csv` file** for each colony — that's the one the dashboard
reads.

Skip these (they're huge and not needed):
- `light-levels.csv` (50–350 MB raw light readings)
- `twilights.csv` (intermediate Hill–Ekström output)
- `barometer.csv` (only on a few colonies)

You do **not** need a Movebank account for these MDR-public datasets.

### Step 3 — place the files

Create the folder `data/raw/movebank/` in the project and drop the CSVs
in. Rename them to make the colony obvious — the loader detects colony
from either the file's `study-name` column or the filename:

```
data/raw/movebank/
├── Switzerland_Baden-tracks.csv
├── Switzerland_Biel-tracks.csv
├── Switzerland_Lausanne-tracks.csv
├── Switzerland_Lenzburg-tracks.csv
├── Switzerland_Solothurn-tracks.csv
└── Spain_Tarragona-tracks.csv
```

(Underscore vs. space doesn't matter; the loader uses case-insensitive
substring matching against `Switzerland Baden`, `Spain Tarragona`, etc.)

### Step 4 — rebuild the cache and launch

In the R console:

```r
# In the project root
unlink("data/processed/tracks_processed.rds")   # invalidate cache
source("R/data_acquisition.R")
source("R/data_processing.R")
build_processed_data(force = TRUE)
shiny::runApp()
```

The startup banner should now read:

> Using REAL Movebank Data Repository tracks.

…instead of the synthetic one. The dashboard will derive annual-cycle
phase (breeding / migration / wintering) automatically from each fix's
position relative to the breeding colony.

## Alternative: live Movebank API

For the missing eastern-flyway colonies (Bulgaria, Turkey, Luzern):

1. Register a free Movebank account at <https://www.movebank.org/>.
2. Find each study (search title "Long term study on migratory movement
   of Alpine swifts"). Click "Request access" and accept the licence.
3. The Swiss Ornithological Institute usually approves academic requests
   within a few days.
4. Once approved, in R:

   ```r
   library(move)
   movebankLogin(username = "your_user", password = "your_pass")
   study <- getMovebankData(study = "Sofia - Long term study...",
                            login = movebankLogin())
   df <- as.data.frame(study)
   write.csv(df, "data/raw/movebank/Bulgaria_Sofia-tracks.csv",
             row.names = FALSE)
   ```

## Recommendation

For an academic deliverable due in two weeks, the **manual MDR download
of the six public colonies is the fastest and fully sufficient** path.
The synthetic eastern-flyway data is clearly labelled in the report and
its presence is scientifically defensible because the assignment
explicitly allows for data-quality compromises so long as they are
documented.
