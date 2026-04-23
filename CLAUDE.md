# CLAUDE.md — landscape_init_ak_can

## Project Overview

R-based landscape initialization pipeline for the **iLand forest simulation model**, generating inputs for boreal forest landscapes across Alaska and Canada. Landscapes were originally selected by Lora Murphy; pipeline adapted by Quinn Asena.

**Full documentation:** `description.qmd` (and rendered `description.html`) — do not regenerate these; they are author-verified.

---

## Pipeline Architecture

13 sequential R scripts in `scripts/`:

| Script | Purpose |
|--------|---------|
| `00_landscape_selection.r` | Select 25 km² plots in boreal ecoregions |
| `01_above_process.r` | Process ABoVE landcover & surface water |
| `02_env.grid_create.r` | Create response unit (RU) grid |
| `03_climate_create.r` | Download downscaled climate data |
| `04_climate_create.r` | Process climate data |
| `05_dem_download.r` | Fetch ArcticDEM tiles |
| `06_dem_process.r` | Process DEM data |
| `07_soil_download.r` | Fetch SoilGrids data |
| `08_soil_process.r` | Process soil composition |
| `09_species_init.r` | Generate sapling initialization table |
| `10_stand.grid_process.r` | Create stand ID grid + species dictionary |
| `11_stand.grid_create.r` | Write ASCII stand grids for iLand |
| `12_env.file_create.r` | Create environment files (RU → climate links) |
| `13_project_file_create.r` | Generate iLand XML project files |

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

## Workflow Split (Important)

```
Local machine (network access)          HPC (NCAR Derecho)
─────────────────────────────           ──────────────────
Run R pipeline (scripts 00–13)   →   Upload outputs   →   Run iLand model
```

**The R pipeline is NOT run on HPC.** It requires local network drive access to source data. The pipeline outputs (grids, climate DBs, XML project files) are uploaded to Derecho, where iLand is executed.

**Hard-coded network paths are intentional:**
- `//10.60.2.10/FF_Lab/` — Winslow's network drive (ABoVE data, climate data)
- `Z:\project_data\na_boreal\` — landscape selection data

---

## Repository Structure

```
scripts/            # 13-step initialization pipeline (00–13_*.r)
data/               # empirical reference data + shared iLand XML templates
anaysis-scripts/    # post-processing R scripts (area dominance, basal area, seed density)
workflow-output/    # Quarto analysis notebooks for iLand output analysis
  workflow-data/    #   data consumed by the analysis notebooks
```

**Pipeline outputs** (git-ignored, per-landscape):
```
<landscape_id>/
  gis/          # spatial grids (ASCII + GeoTIFF)
  init/         # species initialization tables
  databases/    # SQLite climate databases
```

---

## Current Phase

**Local testing + HPC deployment.** See `TODO.md`.

Single-site validation: `cpcrw_test.r` (Caribou-Poker Creeks).

---

## Key Reference Files

- `description.qmd` — comprehensive workflow documentation
- `issues-codex5.3.md` — GPT code review (Priority 1/2 issues; not urgent, kept for reference)
- `NOTES.md` — running decisions log and known gotchas
- `TODO.md` — current phase task tracking
- `iland_scenarios.csv` — iLand scenario parameters
