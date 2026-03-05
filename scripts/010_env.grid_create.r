library(terra)
library(sf)

# FOUND BUG IN TIFFS READ FROM ARIELLE'S DRIVE UPDATED ABOVE DATA CLEAR IT UP
# DO NOT USE THE OLDER ABOVE FILES FROM LORA OR ARIELLE'S OUTPUTS


# This script reproduces "landscape_envgrids.Rmd" from Ariel. ESRI:102001 is equivalent to input file native albers
# The following are Arielle's files from the Z drive, they seem to be from the
# Order matters, first 5 are AK the next 15 are CAN. Make sure order is correct:
landscapes_files <- list.files(path = "//10.60.2.10/FF_Lab/personal_storage/quinn_storage/ak_plot_areas", pattern = "\\.tif$", full.names = TRUE)
landscapes_files <- landscapes_files[order(as.integer(sub(".*?(\\d+)\\.tif$", "\\1", landscapes_files)))]
ak_landcapes <- lapply(landscapes_files, \(ind) {
  out <- file.path(paste0("landscape_", sub(".*?(\\d+)\\.tif$", "\\1", ind)), "gis")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  r0 <- rast(ind)
  r <- project(r0, crs("ESRI:102001"), method = "near", res = 100)
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
