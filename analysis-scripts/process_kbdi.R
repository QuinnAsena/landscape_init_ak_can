# 12 replicate spin-ups were run for all 6 landscapes using a default KBDI
# value of <KBDIref>0.038</KBDIref>.
# Using the spin-up with the closest match to the historic fire regime
# future scenarios spanning 2015-20100 (86 years) were run, as well as
# historic scenarios 1950-2015 (66 years) saving KBDI anually.
# After looking through the results, it was decided that a landscape-specific
# KBDI value derived from the historic runs would improve fire probabilities
# This script calculates a landscape-sprcific KBDI value from the
# historic scenario.

library(terra)
library(tidyr)
library(dplyr)
library(here)

dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])

landscape_cond <- "_onlyfire"
scenario <- "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120_onlyfire_historic"

bind_rows(lapply(landscape_names, function(x) {
  out_dir <- here(x, "supporting_data", "average_kbdi")
  dir.create(out_dir)
  # env.grid for mask
  env_grid_path <- here(x, "gis", "env.grid.tif")
  kbdi_path <- list.files(here(x, "output", paste(x, landscape_cond, sep = ""),
                               scenario, "rep_1", "kbdi"), full.names = TRUE)
  # Remove zeroth year as a raster of all zeros
  kbdi_path <- kbdi_path[!grepl("kbdi_0.txt$", kbdi_path)]
  # Read rasters
  env_grid <- rast(env_grid_path)
  kbdi_rast <- rast(kbdi_path)
  # give the kbdi raster the same CRS as the env.grid raster
  crs(kbdi_rast) <- crs(env_grid)
  # Mask out peremeter of zero-values (whole raster is surrounded by zeros)
  # Also masks out-of-landscape zero-values for CPCRW, which is not a square landscape
  kbdi_rast <- terra::mask(kbdi_rast, env_grid)
  df <- as.data.frame(kbdi_rast, xy = TRUE)

  # Calculate summary statistics as a spatial average across all years
}))

