library(terra)
library(sf)
# This script reproduces "landscape_envgrids.Rmd" from Ariel. ESRI:102001 is equivalent to input file native albers
# The following are Arielle's files from the Z drive, they seem to be from the
# Order matters, first 5 are AK the next 15 are CAN. Make sure order is correct:
dirs <- normalizePath(list.dirs(full.names = TRUE))
ak_landscape_dirs <- dirs[grepl(".*[\\\\/]landscape_[0-9]+$", dirs)]

landscape_ord <- as.integer(
  sub(".*landscape_([0-9]+).*$", "\\1", ak_landscape_dirs)
)
ord <- order(landscape_ord)
ak_landscape_dirs <- ak_landscape_dirs[ord]


ak_landcapes <- lapply(ak_landscape_dirs, \(ind) {
  out <- file.path(ind, "gis")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  above_lc <- list.files(file.path(ind, "ABoVE_LandCover"), full.names = TRUE)

  r0 <- rast(above_lc)
  r <- project(r0[[1]], crs("ESRI:102001"), method = "near", res = 100)
  values(r) <- seq_len(ncell(r))
  names(r) <- "ru"
  writeRaster(r, file.path(out, "env.grid.txt"), overwrite = TRUE, filetype = "AAIGrid", datatype = "INT4S")
  # datatype should be INT4U but that is not handled well by R (https://rdrr.io/cran/terra/man/datatype.html)
  # Probably doesn't matter for ASCII filetype above anyway
  writeRaster(r, file.path(out, "env.grid.tif"), overwrite = TRUE, datatype = "INT4S")
  # 10x10 files are used in step 5 for the DEM, This keeps the 15 classes
  r2 <- terra::disagg(r0, fact = 3, method = "near")
  crs(r2) <- crs(r)
  writeRaster(r2, file.path(out, "env.grid_disagg_10.tif"), overwrite = TRUE, datatype = "INT4S")
})
