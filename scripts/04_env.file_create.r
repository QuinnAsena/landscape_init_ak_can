library(terra)
library(sf)


landscapes_files <- list.files(path = "./data/plot_areas", pattern = "\\.tif$", full.names = TRUE)
landscapes_files[order(as.integer(sub(".*?(\\d+)\\.tif$", "\\1", landscapes_files)))]

ak_landcapes <- lapply(landscapes_files[1:5], \(ind) {
  out <- file.path(paste0("landscape_", sub(".*?(\\d+)\\.tif$", "\\1", ind)), "gis")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  r <- rast(ind)
  r <- terra::disagg(r, fact = 3, method = "near")
  crs(r) <- "ESRI:102001"
  # datatype should be INT4U but that is not handled well by R (https://rdrr.io/cran/terra/man/datatype.html)
  writeRaster(r, file.path(out, "env.grid_disagg_10.tif"), overwrite = TRUE, datatype = "INT4S")
  })


lcp1 <- ak_landcapes[[1]]
forest_msk <- ifel(lcp1 > 4, NA, lcp1)
lcp1_forested <- mask(lcp1, forest_msk)
plot(lcp1_forested)

water_msk <- ifel(lcp1 != 15, NA, lcp1)
lcp1_water <- mask(lcp1, water_msk)
plot(lcp1_water, col = "red")


silt <- rast("Z:/project_data/na_boreal/data_sets/soils/ak/silt_ak.tif")
