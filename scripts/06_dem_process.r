library(terra)
library(here)
# This script is a mashup of Winslow's "forest_products_and_species.Rmd" and 
# Arielle's "landscapes_Alaska5." Mostly became a new script to process DEM files
# downloaded in step 4. hillshade is not necessary, but W uses it for plotting at some point.

# dirs <- list.dirs(here(), recursive = FALSE)
# landscape_dirs <- dirs[grepl("landscape_", basename(dirs))]

perma_rast <- rast("//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/permafrost/permafrost_repr.tif")

process_dem <- function(ak_landscape_dirs, perma_rast) {
  env_files_10m <- list.files(path = here(ak_landscape_dirs, "supporting_data", "gis"), pattern = "env.grid_disagg_10.tif$", full.names = TRUE, recursive = TRUE)
  landscape_names <- basename(ak_landscape_dirs)
  dem_files <- list.files(path = here(ak_landscape_dirs, "supporting_data", "gis", "dem"), pattern = "_dem\\.tif$",full.names = TRUE, recursive = TRUE)
  hillshade_files <- list.files(path = here(ak_landscape_dirs, "supporting_data", "gis", "dem"), pattern = "\\.*browse.tif$", full.names = TRUE, recursive = TRUE)

  print(landscape_names)
  env_grid_10 <- rast(env_files_10m, lyrs = 1)

  perma_lcp <- project(perma_rast, env_grid_10, method = "near") |>
    mask(env_grid_10)

  writeRaster(perma_lcp, filename = here::here(ak_landscape_dirs, "supporting_data", "gis", "permafrost_lcp10.tif"), overwrite = TRUE)

  if (length(dem_files) > 1) {
    dem_rasts <- lapply(dem_files, rast)
    dem_rasts_merge <- do.call(terra::merge, dem_rasts)
    rm(dem_rasts); gc()
    dem_rasts_merge <- project(dem_rasts_merge, env_grid_10, method = "bilinear") |>
      mask(env_grid_10)
  } else {
    dem_rasts_merge <- project(rast(dem_files), env_grid_10, method = "bilinear") |>
      mask(env_grid_10)
  }
  writeRaster(dem_rasts_merge, filename = here::here(ak_landscape_dirs, "supporting_data", "gis", "dem_lcp10.tif"), overwrite = TRUE)
  # terrain() creates NA values around the border of the raster.
  aspect <- terrain(dem_rasts_merge, v = "aspect", unit = "degrees")
  writeRaster(aspect, filename = here::here(landscape_names, "supporting_data", "gis", "aspect_lcp10.tif"), overwrite = TRUE)

  # No slope raster?

  if (length(hillshade_files) > 1) {
    hillshade_rasts <- lapply(hillshade_files, rast)
    hillshade_rasts_merge <- do.call(terra::merge, hillshade_rasts)
    rm(hillshade_rasts); gc()
    hillshade_rasts_merge <- project(hillshade_rasts_merge, env_grid_10, method = "bilinear") |>
      mask(env_grid_10)
  } else {
    hillshade_rasts_merge <- project(rast(hillshade_files), env_grid_10, method = "bilinear") |>
      mask(env_grid_10)
  }
  writeRaster(hillshade_rasts_merge, filename = here::here(landscape_names, "supporting_data", "gis", "hillshade_lcp10.tif"), overwrite = TRUE)
}

#--------------- Run the function ---------------#

dirs <- list.dirs(here(), recursive = FALSE)
landscape_dirs <- dirs[grepl("landscape_", basename(dirs))]

lapply(landscape_dirs, process_dem, perma_rast = perma_rast)
