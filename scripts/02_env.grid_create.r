library(terra)
library(here)
library(future.apply)
# Creates the env.grid raster for each landscape — a 100x100m equal-area grid
# where each cell is assigned a unique sequential RU (resource unit) ID.
# Projects ABoVE land cover tiles to ESRI:102001 (Canada Albers Equal Area),
# which matches the native CRS of the input data.
# Also produces a 10m disaggregated version for use in steps 06 and 07.

process_env_grid <- function(landscape_name) {
  out <- here(landscape_name, "gis")
  out_sup <- here(landscape_name, "supporting_data", "gis")
  dir.create(out_sup, recursive = TRUE, showWarnings = FALSE)
  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  above_lc <- list.files(
    here(landscape_name, "supporting_data", "ABoVE_LandCover"),
    full.names = TRUE)

  r0 <- rast(above_lc, lyrs = 1)
  r <- project(r0, crs("ESRI:102001"), method = "near", res = 100)

  non_na_idx <- which(!is.na(values(r)))
  values(r)[non_na_idx] <- seq_along(non_na_idx)
  png(file.path(out_sup, "env.grid.png"), width = 1200, height = 1000, res = 150)
  plot(r)
  dev.off()
  names(r) <- "ru"
  # ASCII grid format required by iLand
  writeRaster(r, file.path(out, "env.grid.txt"),
              overwrite = TRUE, filetype = "AAIGrid", datatype = "INT4S", NAflag = -1)
  # GeoTIFF for use in subsequent processing steps
  writeRaster(r, file.path(out, "env.grid.tif"),
              overwrite = TRUE, datatype = "INT4S", NAflag = -1)
  # Disaggregate to 10m resolution retaining original 15 land cover classes.
  # Used in step 06 (DEM processing) and step 07 (species initialisation).
  r2 <- terra::disagg(r0, fact = 3, method = "near")
  crs(r2) <- crs(r)
  writeRaster(r2, file.path(out_sup, "env.grid_disagg_10.tif"),
              overwrite = TRUE, datatype = "INT4S", NAflag = -1)
}

#--------------- Run the function ---------------#

dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])

plan(multisession, workers = 21)
future_lapply(landscape_names, process_env_grid, future.seed = TRUE)
plan(sequential)
