library(terra)
library(sf)
library(here)
# This script originated from "landscape_envgrids.Rmd" from Ariel.
# ESRI:102001 is equivalent to input file native albers

dirs <- list.dirs(here(), recursive = FALSE)
landscape_dirs <- dirs[grepl("landscape_", basename(dirs))]

landcapes <- lapply(landscape_dirs, \(ind) {
  out <- file.path(ind, "gis")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  above_lc <- list.files(file.path(ind, "ABoVE_LandCover"), full.names = TRUE)

  r0 <- rast(above_lc)
  r <- project(r0[[1]], crs("ESRI:102001"), method = "near", res = 100)
  plot(ifel(is.na(r), 1, NA))

  non_na_idx <- which(!is.na(values(r)))
  values(r)[non_na_idx] <- seq_along(non_na_idx)
  plot(r)
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
