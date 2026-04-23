# CLAUDE.md — landscape_init_ak_can

## Project Overview

R-based landscape initialization pipeline for the **iLand forest simulation model**, generating spatial and ecological inputs for boreal forest landscapes across Alaska and Canada. Landscapes were originally selected by Lora Murphy; pipeline adapted by Quinn Asena.

**Full documentation:** `scripts/description.qmd` (and rendered `description.html`) — comprehensive workflow reference, kept up to date alongside the scripts.

---

## Pipeline Architecture

13 sequential R scripts in `scripts/`:

| Script | Purpose |
|--------|---------|
| `00_landscape_selection.r` | Select 25 km² plots in boreal ecoregions |
| `01_above_process.r` | Crop ABoVE land cover & surface water to each landscape polygon |
| `02_env.grid_create.r` | Create 100m RU (resource unit) grid + aligned 10m land cover grid |
| `03_climate_create.r` | Extract downscaled climate data per landscape; write RU→climate-cell link |
| `04_climate_create.r` | Compile per-landscape climate text files into SQLite databases |
| `05_dem_download.r` | Fetch ArcticDEM tiles via PGC STAC API |
| `06_dem_process.r` | Reproject DEM; derive aspect, hillshade, permafrost per landscape |
| `07_soil_download.r` | Fetch SoilGrids tiles via ISRIC WCS API |
| `08_soil_process.r` | Depth-weighted soil means; normalise sand/silt/clay to sum 100 |
| `09_species_init.r` | Assign initial forest species per RU from land cover, aspect, permafrost |
| `10_stand.grid_process.r` | Fit height distributions; generate sapling init table + stand dictionary |
| `11_stand.grid_create.r` | Randomly assign stand IDs to RU cells |
| `12_env.file_create.r` | Build iLand environment file (soil, carbon pools, climate links) |
| `13_project_file_create.r` | Generate iLand XML project files; copy shared assets to landscapes |

---

## Tech Stack

- **Language:** R
- **Spatial:** `terra`, `sf`
- **Data:** `dplyr`, `tidyr`, `purrr`, `lubridate`
- **Database:** `DBI`, `RSQLite`
- **APIs:** `rstac` (ArcticDEM), `geodata` (SoilGrids)
- **Parallel:** `future.apply`
- **XML:** `xml2`
- **Stats:** `fitdistrplus`

---

## Three-Machine Workflow

```
Local laptop          Network machine ("Cuddles")        HPC (NCAR Derecho)
─────────────         ──────────────────────────         ──────────────────
Script edits   →   Run R pipeline (scripts 01–13)  →   Upload outputs  →  Run iLand
                   (needs network drive access)
```

- **Local laptop:** Script editing. Cannot run data-heavy scripts (no network drive).
- **Network machine ("Cuddles"):** Runs all pipeline scripts; reads/writes large data to `//10.60.2.10/FF_Lab/`. Hard-coded network paths are intentional.
- **HPC (Derecho):** Runs iLand per landscape. Pipeline outputs are uploaded here. `run_iland_csv_cpxml.sh` manages execution.

All three machines sync via git/GitHub. Large data outputs are `.gitignore`d.

**Hard-coded network paths:**
- `//10.60.2.10/FF_Lab/` — Winslow's network drive (ABoVE data, climate, permafrost)

---

## Critical Technical Details

### Grid alignment (scripts 01–02, 06, 09)
The ABoVE land cover product has 30m cells. A direct `disagg(fact=3)` → `aggregate(fact=10)` workflow fails because the cropped raster dimensions are not exact multiples of 10 (e.g. 1163 / 10 = 116.3), producing partial edge groups and misaligned 100m/10m grids. The fix:

1. **Snap** the bounding extent to 100m boundaries before building the grid.
2. **`resample()`** the 30m land cover to the snapped 10m template (nearest-neighbour).
3. **`aggregate(fact=10, na.rm=FALSE)`** — only fully-covered 100m blocks become valid RUs; partial boundary blocks are excluded.
4. **`mask(above_10, disagg(above_100, fact=10))`** — the 10m grid is masked to exactly the 100m footprint, guaranteeing pixel-exact consistency between `env.grid.tif` and `env.grid_disagg_10.tif`.

Using `na.rm=TRUE` instead expands the landscape by ~1% (partial boundary blocks included); if desired, uncomment the buffer code in `01_above_process.r` to fill sub-cell NAs via `cover()`.

The same misalignment affects the 30m water raster in script 09 — fixed by `project(water_rast, rasters$env_grid_10, method="near")` instead of `disagg()`.

### Soil normalisation (script 08)
Sand and clay are rounded as proportions of the true depth-weighted total; silt is the exact residual (100 − sand − clay). This guarantees sand + silt + clay = 100 for every cell regardless of rounding.

### iLand on Windows — bash path handling
`run_iland_csv_cpxml.sh` uses `cygpath -m` (not `-w`) to convert POSIX paths to Windows format after `realpath`. `-w` produces backslashes which sed interprets as escape sequences (`\l` = lowercase next char, etc.), mangling paths like `\landscape_*` → `andscape_*`. `-m` gives forward-slash Windows paths (`Z:/...`) safe for both sed and native Windows iLand.

### Climate table naming contract
`build_env_file_link` (script 12) constructs climate table names as `<landscape_name>_<climate_grid_cell_id>`. The SQLite tables written in script 04 must use the same naming scheme. Do not use `build_env_file` (which keys on RU ID) unless the climate database is rebuilt to match.

---

## Repository Structure

```
scripts/             # 13-step initialization pipeline (00–13_*.r)
                     # + description.qmd (workflow documentation)
data/
  empirical/         # Johnstone/Walker stand data; sapinit_dict.txt
  landscape_selection/ # Landscape polygons (final_plots_above_proj.shp)
  cpcrw/             # CPCRW extent raster
  shared-xml-create/ # Master XML template, spp_param.sqlite, lip/, saveWorkflow.js
analysis-scripts/    # Post-processing R scripts
workflow-output/     # Quarto analysis notebooks + workflow-data/
```

Per-landscape outputs (git-ignored):
```
landscape_<region>_<nn>/
  <name>_<years><run_type>.xml   # iLand project file
  gis/                           # env.grid, DEM, stand_grid, env.file (iLand inputs)
  init/                          # landscape_model_init.txt
  databases/                     # climate SQLite + spp_param.sqlite
  lip/ scripts/ output/ snapshot/ temp/ log/
  supporting_data/               # intermediate files (not read by iLand)
    ABoVE_LandCover/ ABoVE_Water/
    climate_link/
    dem/
    gis/                         # env.grid_disagg_10.tif, aspect, DEM, permafrost, species init
    soils/ soils_processed/
```

---

## Current Phase

**Local testing + HPC deployment.** See `TODO.md`.

Single-site validation: `cpcrw_test.r` (Caribou-Poker Creeks).

---

## Key Reference Files

- `scripts/description.qmd` — comprehensive workflow documentation (kept current)
- `NOTES.md` — running decisions log and known gotchas
- `TODO.md` — current phase task tracking
- `iland_scenarios.csv` — iLand scenario parameters (GCM, SSP, fire, epsilon, DBH, stand/env file variants)
- `run_iland_csv_cpxml.sh` — shell script to execute iLand locally and on Derecho
- `issues-codex5.3.md` — GPT code review (Priority 1/2 issues; not urgent, kept for reference)
