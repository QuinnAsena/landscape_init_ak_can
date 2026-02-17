library(terra)
library(purrr)
library(dplyr)

dirs <- normalizePath(list.dirs(full.names = TRUE))
ak_landscape_dirs <- dirs[grepl(".*[\\\\/]landscape_[0-9]+$", dirs)]

landscape_ord <- as.integer(
  sub(".*landscape_([0-9]+).*$", "\\1", ak_landscape_dirs)
)
ord <- order(landscape_ord)
ak_landscape_dirs <- ak_landscape_dirs[ord]




ak_landscape_dirs <- ak_landscape_dirs[1]

layers <- c(
  dem        = "dem_lcp10.tif",
  aspect     = "aspect_lcp10.tif",
  hillshade  = "hillshade_lcp10.tif",
  env_grid   = "env.grid_disagg_10.tif",
  permafrost = "permafrost_lcp10.tif"
)

rasters <- lapply(file.path(ak_landscape_dirs, "gis", layers), rast)
names(rasters) <- names(layers)

raster_df <- lapply(rasters, as.data.frame, xy = TRUE) |>
  purrr::reduce(dplyr::left_join, by = c("x", "y"))

head(raster_df)
tail(raster_df)

dem_10 <- rast(file.path(ak_landscape_dirs, "gis", "dem_lcp10.tif"))
aspect_10 <- rast(file.path(ak_landscape_dirs, "gis", "aspect_lcp10.tif"))
hillshade_10 <- rast(file.path(ak_landscape_dirs, "gis", "hillshade_lcp10.tif"))
env_grid_10m <- rast(file.path(ak_landscape_dirs, "gis", "env.grid_disagg_10.tif"))
perma_10 <- rast(file.path(ak_landscape_dirs, "gis", "permafrost_lcp10.tif"))

ext(aspect_10)
ext(env_grid_10m)

tst <- aspect_10 |>
  as.data.frame(xy = TRUE)
any(is.na(tst$aspect))

r_stack <- rast(rasters)
raster_df <- as.data.frame(r_stack, xy = TRUE)
head(raster_df)

sum(is.na(raster_df$aspect))
sum(is.na(raster_df$permafrost))

compareGeom(rasters[[1]], rasters[[2]], stopOnError = TRUE)
compareGeom(rasters[[1]], rasters[[3]], stopOnError = TRUE)
compareGeom(rasters[[1]], rasters[[4]], stopOnError = TRUE)
compareGeom(rasters[[1]], rasters[[5]], stopOnError = TRUE)

