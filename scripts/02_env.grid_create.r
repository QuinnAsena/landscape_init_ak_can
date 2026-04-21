library(terra)
library(here)
# Creates the env.grid raster for each landscape — a 100x100m equal-area grid
# where each cell is assigned a unique sequential RU (resource unit) ID.
# Also produces a 10m version retaining land cover classes for use in steps 06 and 09.
#
# WHY WE SNAP TO A GRID BEFORE AGGREGATING
# -----------------------------------------
# The ABoVE land cover product has 30m cells in ESRI:102001 (Canada Albers Equal
# Area). After cropping to a landscape polygon, irregular rasters like CPCRW may
# have dimensions like 1163 rows × 1165 cols. Dividing by the scale factor needed
# to reach 100m(30 → 10 requires factor 3; 10 → 100 requires factor 10,
# so overall 30 × 3.33):
#
#   disagg(above_30, fact = 3)  →  3489 × 3495
#   3489 / 10 = 348.9    ← not an integer!
#   3495 / 10 = 349.5    ← not an integer!
#
# aggregate(fact = 10) on a grid whose dimensions are not divisible by 10 produces
# partial groups at the edges. Those edge 100m cells cover fewer than 100 10m
# sub-cells, so the modal land-cover assignment is based on partial data and the
# resulting env.grid and env.grid_disagg_10 are not in exact pixel alignment.
# This misalignment propagates through every downstream script (06, 09, 11, 12)
# that joins the two grids, causing NA cells and incorrect species assignments
# in the stand.grid gains the env.grid.
#
# The fix: snap the extent to 100m boundaries BEFORE resampling. This guarantees
# that nrow(above_10) and ncol(above_10) are exact multiples of 10, so every
# aggregate() output cell covers exactly 10×10 input cells — no partial groups.
# Cells added at the bounding-box edges receive NA from resample() and never
# acquire RU IDs, so no post-cropping is needed.
# This probably is not an issue with the all
# other landscapes now that they are projected to equal Albers (in the adjusted
# version of Lora's script) and should have equal dimensions. But I wated to make
# the script generalisable.
#
# WHY na.rm = FALSE IN aggregate()
# ----------------------------------
# With the snapped grid, every aggregate() group covers exactly 10×10 cells, so
# there are no partial-group edge artefacts regardless of na.rm. We use
# na.rm = FALSE to keep only 100m blocks where all 100 sub-cells are non-NA —
# i.e., only fully-covered blocks entirely within the landscape polygon. This
# avoids including boundary blocks where the polygon clips through a cell, which
# would have incomplete 10m sub-cell coverage and potentially mis-assigned species.
# above_10 is then masked to the same footprint, so env.grid and
# env.grid_disagg_10 are guaranteed to be exactly consistent.
#
# Alternative: na.rm = TRUE includes any 100m block with at least one non-NA
# sub-cell, expanding the landscape by ~1% at the boundary. If that is desired,
# use cover(above_10, resample(above_30_buff, r_template_10, method = "near"))
# before the mask step — the 1000m-buffered land cover saved in step 01 fills the
# NA sub-cells so every included boundary block has complete 10m coverage.

process_env_grid <- function(landscape_name) {
  out <- here(landscape_name, "gis")
  out_sup <- here(landscape_name, "supporting_data", "gis")
  dir.create(out_sup, recursive = TRUE, showWarnings = FALSE)
  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  above_lc <- list.files(
    here(landscape_name, "supporting_data", "ABoVE_LandCover"),
    pattern = "ABoVE_LandCover\\.tif$", full.names = TRUE)

  above_30 <- rast(above_lc)

  # Snap extent to 100m boundaries. Cells added beyond above_30's original extent
  # receive NA from resample() and never acquire RU IDs — no post-crop needed.
  e <- ext(above_30)
  e_snap <- ext(
    floor(xmin(e)   / 100) * 100,
    ceiling(xmax(e) / 100) * 100,
    floor(ymin(e)   / 100) * 100,
    ceiling(ymax(e) / 100) * 100
  )
  nrows_100 <- round((ymax(e_snap) - ymin(e_snap)) / 100)
  ncols_100 <- round((xmax(e_snap) - xmin(e_snap)) / 100)
  r_template_100 <- rast(e_snap, nrows = nrows_100, ncols = ncols_100, crs = crs(above_30))
  r_template_10  <- disagg(r_template_100, fact = 10)

  # Resample all land-cover layers to the snapped 10m grid.
  # Nearest-neighbour preserves integer class codes.
  above_10 <- resample(above_30, r_template_10, method = "near")

  # na.rm = FALSE: only 100m blocks where all 100 sub-cells are non-NA become
  # valid RUs. See header comment for the na.rm = TRUE / buffer alternative.
  above_100 <- aggregate(above_10[[1]], fact = 10, fun = "modal", na.rm = FALSE)

  # Mask above_10 to the same footprint as above_100 so the two grids are
  # exactly consistent — no 10m sub-cells outside a valid 100m RU.
  above_10 <- mask(above_10, disagg(above_100, fact = 10))

  # create sequential RU IDs for non-NA cells at 100x100
  non_na_idx <- which(!is.na(values(above_100)))
  values(above_100)[non_na_idx] <- seq_along(non_na_idx)
  png(file.path(out_sup, "env.grid.png"), width = 1200, height = 1000, res = 150)
  plot(above_100)
  dev.off()
  names(above_100) <- "ru"
  # ASCII grid format required by iLand
  writeRaster(above_100, file.path(out, "env.grid.txt"),
              overwrite = TRUE, filetype = "AAIGrid", datatype = "INT4S", NAflag = -1)
  # GeoTIFF for use in subsequent processing steps
  writeRaster(above_100, file.path(out, "env.grid.tif"),
              overwrite = TRUE, datatype = "INT4S", NAflag = -1)
  # 10m land cover grid, masked to exactly the above_100 footprint.
  # Used in step 06 (DEM processing) and step 09 (species initialisation).
  writeRaster(above_10, file.path(out_sup, "env.grid_disagg_10.tif"),
              overwrite = TRUE, datatype = "INT4S", NAflag = -1)
}

#--------------- Run the function ---------------#

dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])

lapply(landscape_names, process_env_grid)
