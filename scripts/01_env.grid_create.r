library(terra)
library(sf)

# The following are Arielle's files from the Z drive, they seem to be from the
# Order matters, first 5 are AK the next 15 are CAN. Make sure order is correct:
landscapes_files <- list.files(path = "./data/plot_areas", pattern = "\\.tif$", full.names = TRUE)
landscapes_files[order(as.integer(sub(".*?(\\d+)\\.tif$", "\\1", landscapes_files)))]
# project(r, daymet_studyarea) to preserve 30x30 resolution of landscape files with method = "near" to preserve categories.
ak_landcapes <- lapply(landscapes_files[1:5], \(ind) {
  out <- file.path(paste0("landscape_", sub(".*?(\\d+)\\.tif$", "\\1", ind)), "gis")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  r <- rast(ind)
  r <- project(r, crs("ESRI:102001"), method = "near", res = 100)
  values(r) <- seq_len(ncell(r))
  names(r) <- "ru"
  writeRaster(r, file.path(out, "env.grid.txt"), overwrite = TRUE, filetype = "AAIGrid", datatype = "INT4S")
  # datatype should be INT4U but that is not handled well by R (https://rdrr.io/cran/terra/man/datatype.html)
  # Probably doesn't matter for ASCII filetype above anyway
  writeRaster(r, file.path(out, "env.grid.tif"), overwrite = TRUE, datatype = "INT4S")
})
