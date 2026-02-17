library(terra)
library(here)

perma_rast <- rast("Z:/project_data/na_boreal/data_sets/permafrost/permafrost_repr.tif")

process_dem <- function(ak_landscape_dirs, perma_rast) {
  env_files_10m <- list.files(path = ak_landscape_dirs, pattern = "env.grid_disagg_10.tif$", full.names = TRUE, recursive = TRUE)
  landscape_names <- sub(".*(landscape_[0-9]+).*", "\\1", env_files_10m)
  dem_files <- list.files(path = ak_landscape_dirs, pattern = "_dem\\.tif$",full.names = TRUE, recursive = TRUE)
  hillshade_files <- list.files(path = ak_landscape_dirs, pattern = "\\.*browse.tif$", full.names = TRUE, recursive = TRUE)

  env_grid_10 <- rast(env_files_10m)

  perma_lcp <- project(perma_rast, env_grid_10, method = "near")
  writeRaster(perma_lcp, filename = here::here(landscape_names, "gis", "permafrost_lcp10.tif"), overwrite = TRUE)

  if (length(dem_files) > 1) {
    dem_rasts <- lapply(dem_files, rast)
    dem_rasts_merge <- do.call(terra::merge, dem_rasts)
    rm(dem_rasts); gc()
    dem_rasts_merge <- project(dem_rasts_merge, env_grid_10, method = "bilinear")
  } else {
    dem_rasts_merge <- project(rast(dem_files), env_grid_10, method = "bilinear")
  }
  writeRaster(dem_rasts_merge, filename = here::here(landscape_names, "gis", "dem_lcp10.tif"), overwrite = TRUE)

  aspect <- terrain(dem_rasts_merge, v = "aspect", unit = "degrees")
  writeRaster(aspect, filename = here::here(landscape_names, "gis", "aspect_lcp10.tif"), overwrite = TRUE)

  if (length(hillshade_files) > 1) {
    hillshade_rasts <- lapply(hillshade_files, rast)
    hillshade_rasts_merge <- do.call(terra::merge, hillshade_rasts)
    rm(hillshade_rasts); gc()
    hillshade_rasts_merge <- project(hillshade_rasts_merge, env_grid_10, method = "bilinear")
  } else {
    hillshade_rasts_merge <- project(rast(hillshade_files), env_grid_10, method = "bilinear")
  }
  writeRaster(hillshade_rasts_merge, filename = here::here(landscape_names, "gis", "hillshade_lcp10.tif"), overwrite = TRUE)

}

dirs <- normalizePath(list.dirs(full.names = TRUE))
ak_landscape_dirs <- dirs[grepl(".*[\\\\/]landscape_[0-9]+$", dirs)]

landscape_ord <- as.integer(
  sub(".*landscape_([0-9]+).*$", "\\1", ak_landscape_dirs)
)
ord <- order(landscape_ord)
ak_landscape_dirs <- ak_landscape_dirs[ord]

lapply(ak_landscape_dirs, process_dem, perma_rast = perma_rast)
