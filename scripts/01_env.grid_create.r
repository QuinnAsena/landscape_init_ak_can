library(terra)
library(sf)

# I'm taking daymet studyarea (from Jaz) as a template since it is in the same projection
# as the downscaled climate data (see test_pad and Winslow scripts). Arielle uses ESRI:102001"

# daymet_studyarea <- rast('./data/ak_noislands_daymetpixels.tif')
# The following are Arielle's files from the Z drive, they seem to be from the 
# ABOVE 15 dataset, I'm not sure where the plot area came from.
# Order matters, first 5 are AK the next 15 are CAN. Make sure order is correct:
landscapes_files <- list.files(path = "./data/plot_areas", pattern = "\\.tif$", full.names = TRUE)
landscapes_files[order(as.integer(sub(".*?(\\d+)\\.tif$", "\\1", landscapes_files)))]
# The following is adapted from Arielle. She uses crs(raster) <- "ESRI:102001", this relabels but does not reproject.
# I am using project() to project to the daymet crs, and project(r, crs(daymet_studyarea), method = "near") instead of
# project(r, daymet_studyarea) to preserve 30x30 resolution of landscape files with method = "near" to preserve categories.
ak_landcapes <- lapply(landscapes_files[1:5], \(ind) {
  out <- file.path(paste0("landscape_", sub(".*?(\\d+)\\.tif$", "\\1", ind)), "gis")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  
  r <- rast(ind)
  # r <- project(r, crs(daymet_studyarea), method = "near", res = 100)
  r <- project(r, crs("ESRI:102001"), method = "near", res = 100)
  values(r) <- seq_len(ncell(r))
  names(r) <- "ru"
  writeRaster(r, file.path(out, "env.grid.txt"), overwrite = TRUE, filetype = "AAIGrid", datatype = "INT4S")
  # datatype should be INT4U but that is not handled well by R (https://rdrr.io/cran/terra/man/datatype.html)
  # Probably doesn't matter for ASCII filetype above anyway
  writeRaster(r, file.path(out, "env.grid.tif"), overwrite = TRUE, datatype = "INT4S")
  })
