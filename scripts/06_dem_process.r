library(terra)
library(here)
library(future.apply)
# Processes ArcticDEM tiles downloaded in step 05 for each landscape.
# Projects and masks DEM, aspect, hillshade, and permafrost to the 10m
# landscape grid. Aspect is computed before masking to avoid NA border values
# that would otherwise result from edge cells lacking neighbours.
# Outputs are saved to supporting_data/gis/ for use in step 07.
# Based on Winslow's "forest_products_and_species.Rmd" and Arielle's "landscapes_Alaska5."

perma_rast <- rast("//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/permafrost/permafrost_repr.tif")

process_dem <- function(landscape_name, perma_rast) {
  env_files_10m <- list.files(
    path = here(landscape_name, "supporting_data", "gis"),
    pattern = "env.grid_disagg_10.tif$",
    full.names = TRUE,
    recursive = TRUE)
  dem_files <- list.files(
    path = here(landscape_name, "supporting_data", "gis", "dem"),
    pattern = "_dem\\.tif$",
    full.names = TRUE,
    recursive = TRUE)
  hillshade_files <- list.files(
    path = here(landscape_name, "supporting_data", "gis", "dem"),
    pattern = "\\.*browse.tif$",
    full.names = TRUE,
    recursive = TRUE)

  env_grid_10 <- rast(env_files_10m, lyrs = 1)
  env_grid_10_buff <- buffer(env_grid_10, width = 1000)

  perma_lcp <- project(perma_rast, env_grid_10, method = "near") |>
    mask(env_grid_10)
  writeRaster(perma_lcp,
              filename = here(landscape_name, "supporting_data", "gis", "permafrost_lcp10.tif"),
              overwrite = TRUE)

  if (length(dem_files) > 1) {
    dem_rasts_merge <- project(vrt(dem_files),
                               env_grid_10_buff, method = "bilinear") |>
      mask(env_grid_10_buff)
  } else {
    dem_rasts_merge <- project(rast(dem_files), env_grid_10_buff, method = "bilinear") |>
      mask(env_grid_10_buff)
  }

  # Compute aspect on the buffered, unmasked DEM so that border cells have
  # valid neighbours — masking afterwards removes the buffer fringe
  aspect <- terrain(dem_rasts_merge, v = "aspect", unit = "degrees")
  aspect <- mask(aspect, env_grid_10)
  writeRaster(aspect,
              filename = here(landscape_name, "supporting_data", "gis", "aspect_lcp10.tif"),
              overwrite = TRUE)

  dem_rasts_merge <- mask(dem_rasts_merge, env_grid_10)
  writeRaster(dem_rasts_merge,
              filename = here(landscape_name, "supporting_data", "gis", "dem_lcp10.tif"),
              overwrite = TRUE)

  writeRaster(dem_rasts_merge, here(landscape_name, "gis", "DEM_processed.txt"),
              overwrite = TRUE, filetype = "AAIGrid", datatype = "INT4S", NAflag = -1)

  writeRaster(dem_rasts_merge, here(landscape_name, "gis", "DEM_processed.tif"),
              overwrite = TRUE, datatype = "INT4S", NAflag = -1)

  # Slope is not currently used by iLand but could be added here if needed

  if (length(hillshade_files) > 1) {
    hillshade_rasts_merge <- project(vrt(hillshade_files),
                                     env_grid_10, method = "bilinear") |>
      mask(env_grid_10)
  } else {
    hillshade_rasts_merge <- project(rast(hillshade_files), env_grid_10, method = "bilinear") |>
      mask(env_grid_10)
  }
  writeRaster(hillshade_rasts_merge,
              filename = here(landscape_name, "supporting_data", "gis", "hillshade_lcp10.tif"),
              overwrite = TRUE)
}

#--------------- Run the function ---------------#

dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])

plan(multisession, workers = 3)
future_lapply(landscape_names, process_dem, perma_rast = perma_rast,
              future.seed = TRUE)
plan(sequential)
