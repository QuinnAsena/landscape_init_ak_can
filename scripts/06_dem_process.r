library(terra)
library(here)
library(future.apply)
# Processes ArcticDEM tiles downloaded in step 05 for each landscape.
# Projects and masks DEM, aspect, hillshade, and permafrost to the 10m
# landscape grid. Aspect is computed before masking to avoid NA border values
# that would otherwise result from edge cells lacking neighbours.
# Outputs are saved to supporting_data/gis/ for use in step 07.
# Based on Winslow's "forest_products_and_species.Rmd" and Arielle's "landscapes_Alaska5."


process_dem <- function(landscape_name, perma_rast) {
  # perma_rast is too large to wrap, commenting-out
  # if (inherits(perma_rast, "PackedSpatRaster")) {
  #   perma_rast <- unwrap(perma_rast)
  # }

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

  perma_lcp <- project(perma_rast, env_grid_10, method = "near") |>
    mask(env_grid_10)
  writeRaster(perma_lcp,
              filename = here(landscape_name, "supporting_data", "gis",
                              "permafrost_lcp10.tif"),
              overwrite = TRUE)

  # Project DEM to the landscape CRS and resolution without restricting to the
  # landscape extent — the downloaded tiles cover a 1000m buffer (step 05) so
  # the projected raster extends beyond the landscape boundary. Aspect is then
  # computed on this full extent so border cells have valid neighbours, before
  # masking back to env_grid_10 removes the fringe.
  dem_src <- if (length(dem_files) > 1) vrt(dem_files) else rast(dem_files)

  # Extend env_grid_10 by 10 cells (1000m) to create a buffered template that
  # shares the same grid origin — projecting to this ensures cell alignment so
  # crop() and mask() back to env_grid_10 work without extent mismatch errors.
  # Project the buffered extent to the DEM's native CRS for cropping.
  env_grid_10_ext <- extend(env_grid_10, 10)
  dem_ext_dem_crs <- project(ext(env_grid_10_ext),
                             from = crs(env_grid_10), to = crs(dem_src))
  dem_rasts_merge <- crop(dem_src, dem_ext_dem_crs) |>
    project(env_grid_10_ext, method = "bilinear")

  # Compute aspect on the buffered DEM so border cells have valid neighbours
  aspect <- terrain(dem_rasts_merge, v = "aspect", unit = "degrees")
  aspect <- crop(aspect, env_grid_10) |> mask(env_grid_10)

  writeRaster(aspect,
              filename = here(landscape_name, "supporting_data", "gis", "aspect_lcp10.tif"),
              overwrite = TRUE)

  dem_rasts_merge <- crop(dem_rasts_merge, env_grid_10) |> mask(env_grid_10)

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
perma_rast <- rast("//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/permafrost/permafrost_repr.tif")

# If sequential, use regular raster
lapply(landscape_names, process_dem, perma_rast = perma_rast)

# perma_rast too big to wrap, go sequential
# Wrapping the raster will take a while!
# Only necessary if running in parallel is worthwhile
# perma_rast_wrapped <- terra::wrap(perma_rast)
# Use wrapped raster in parallel
# plan(multisession, workers = 2)
# future_lapply(landscape_names, process_dem, perma_rast = perma_rast_wrapped,
              # future.seed = TRUE)
# plan(sequential)
