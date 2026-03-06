library(terra)
library(here)
# Above landcover has 1 tif per tile with 31 lyrs (1 per yr)
# https://www.earthdata.nasa.gov/data/catalog/ornl-cloud-annual-landcover-above-1691-1
above_lc_files <- list.files(
  "//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/Annual_Landcover_ABoVE_1691/data",
  pattern = "\\.tif$", full.names = TRUE)
# Filter out 10 class
above_lc_files <- above_lc_files[!grepl(pattern = "Simplified", above_lc_files)]

# Above surface water files have a tif per tile per decade so we deal with that later
#https://www.earthdata.nasa.gov/data/catalog/ornl-cloud-decadal-water-maps-1324-1.1
above_water_files <- list.files(
  "//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/Decadal_Water_Maps_1324/data",
  pattern = "\\.tif$", full.names = TRUE)
# Filter out Quality Assurance
above_water_files <- above_water_files[!grepl(pattern = "QA", above_water_files)]

# Load up Lora's selected landscapes
landscapes_poly <- vect("//10.60.2.10/FF_Lab/project_data/na_boreal/Landscape building/Landscape selection/Selected plots/final_plots.shp")


# Awkwardly stich cpcrw on
cpcrw <- rast("D:/quinn/GitHub/landscape_init_ak_can/data/cpcrw/env.grid.tif")
cpcrw_poly <- as.polygons(cpcrw, extent = TRUE) |>
  project(crs(landscapes_poly))
plot(cpcrw_poly)
same.crs(cpcrw_poly, landscapes_poly)

cpcrw_poly_proj$ID            <- 1
cpcrw_poly_proj$ecoregion     <- "ALASKA CPCRW"
cpcrw_poly_proj$Propforest     <- NA
cpcrw_poly_proj$Suppressio     <- NA

landscapes_poly <- rbind(cpcrw_poly_proj, landscapes_poly)


landscapes_poly$landscape_id <- ifelse(
  grepl("ALASKA", landscapes_poly$ecoregion),
  paste0("alaska_landscape_", sprintf("%02d", seq_len(nrow(landscapes_poly)))),
  paste0("canada_landscape_", sprintf("%02d", seq_len(nrow(landscapes_poly))))
)


# Create vrt once outside function
above_lc_vrt <- vrt(above_lc_files, set_names = TRUE)
# set_names uses names from first tile and so will be incorrect ref
names(above_lc_vrt) <- gsub("Bh01v02_", "", names(above_lc_vrt))

#  Here we convert the surface water to  have three layers in the tif (1 per decade)
above_water_file_names <- basename(above_water_files)
decades <- sub(".*_(\\d{4})\\.tif$", "\\1", above_water_file_names)
above_water_decade <- split(above_water_files, decades)

water_vrt_decade <- lapply(above_water_decade, \(r) {
  v <- vrt(r, set_names = TRUE) # vrt all tiles
  names(v) <- gsub("h00v00_", "", names(v))
  v
})
# combine to 1 layer per decade
water_vrt <- Reduce(c, water_vrt_decade)




crop_lcp <- function(lcp_vrt, poly) {
  lcp <- paste0("landscape_", poly$landscape_id)
  nm <- sub("_\\d+$", "", names(lcp_vrt)[1])
  out <- file.path(here(), lcp, nm)
  dir.create(out, recursive = TRUE)

  if (!same.crs(lcp_vrt, poly)) {
    warning("Check on crs in: ", lcp, "\nprojecting to ", crs(lcp_vrt))
    poly <- project(poly, crs(lcp_vrt))
  }

  vrt_crop <- suppressWarnings(crop(lcp_vrt, poly, mask = TRUE))

  writeRaster(vrt_crop, file.path(out, paste0(nm, ".tif")), overwrite = TRUE, datatype = "INT4S")
}


landscapes <- lapply(
  seq_len(nrow(landscapes_poly)),
  \(i) crop_lcp(above_lc_vrt, landscapes_poly[i, ])
)

landscapes <- lapply(
  seq_len(nrow(landscapes_poly)),
  \(i) crop_lcp(water_vrt, landscapes_poly[i, ])
)






# Now we crop all 5 landscapes out of the vrt and save the rasters
vrt_lcp <- function(lcp_vrt, landscapes_file) {
  nm <- sub("_\\d+$", "", names(lcp_vrt)[1])
  lcp_nm <- file.path(paste0("landscape_", sub(".*?(\\d+)\\.tif$", "\\1", landscapes_file)))
  out <- file.path(here(), lcp_nm, nm)
  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  lcp_crop_area <- rast(landscapes_file)

  if (!same.crs(lcp_crop_area, lcp_vrt)) {
    stop("Check on crs")
  }
  vrt_crop <- crop(lcp_vrt, lcp_crop_area, mask = TRUE)

  writeRaster(vrt_crop, file.path(out, paste0(nm, ".tif")), overwrite = TRUE, datatype = "INT4S")
}

lapply(landscapes_files, vrt_lcp, lcp_vrt = above_lc_vrt)
lapply(landscapes_files, vrt_lcp, lcp_vrt = water_vrt)

tst <- rast("D:/quinn/GitHub/landscape_init_ak_can/landscape_06/ABoVE_LandCover/ABoVE_LandCover.tif")
plot(tst[[1]])
tst1 <- ifel(is.na(tst), 1, NA)
plot(tst1)
tst2 <- rast("D:/quinn/GitHub/landscape_init_ak_can/landscape_01/ABoVE_Water/ABoVE_Water.tif")
plot(tst2)


landscapes_poly <- vect("//10.60.2.10/FF_Lab/project_data/na_boreal/Landscape building/Landscape selection/Selected plots/final_plots.shp")

landscapes <- lapply(seq_len(nrow(landscapes_poly)), \(i) {
  lcp_crop <- crop(above_lc_vrt, landscapes_poly[i, ], mask = TRUE)
})






















# We are using the plot areas even though they already are the above lc data
landscapes_poly <- vect("Z:/project_data/na_boreal/Landscape building/Landscape selection/Selected plots/final_plots.shp")
plot(landscapes_poly)
r <- rast(above_lc_files[4])
same.crs(r, landscapes_poly)

above_tst_crop <- crop(above_lc_vrt, landscapes_poly[1, ], mask = TRUE)
plot(above_tst_crop[[1]])
tst <- rast("D:/quinn/GitHub/landscape_init_ak_can/landscape_01/ABoVE_LandCover/ABoVE_LandCover.tif")
plot(tst)
compareGeom(above_tst_crop, tst)
all.equal(above_tst_crop, tst)

above_tst_crop2 <- crop(above_lc_vrt, landscapes_poly[1, ], mask = TRUE)
plot(above_tst_crop2)

cpcrw_ru <- rast("D:/quinn/GitHub/iLand_automated/gis/env.grid.tif")
plot(cpcrw_ru)

cpcrw <- rast("Z:/personal_storage/quinn_storage/ak_plot_areas/env.grid_cpcrw06.tif")
plot(cpcrw)







# We are using the plot areas even though they already are the above lc data
cpcrw_landscapes_files <- list.files(
  path = "//10.60.2.10/FF_Lab/personal_storage/quinn_storage/ak_plot_areas",
  pattern = "\\.tif$", full.names = TRUE)

cpcrw_landscapes_files <- cpcrw_landscapes_files[!grepl(pattern = "landscapes", cpcrw_landscapes_files)]

cpcrw_names <- basename(cpcrw_landscapes_files)

cpcrw_rasts <- lapply(cpcrw_landscapes_files, rast)
names(cpcrw_rasts) <- cpcrw_names

plot(cpcrw_rasts$env.grid.tif)
plot(cpcrw_rasts$env.grid_cpcrw06.tif)
plot(cpcrw_rasts$forest_species_init.tif)
plot(cpcrw_rasts$master_gridf.tif)
plot(cpcrw_rasts$stand_grid.tif)


env.grid_proj <- project(cpcrw_rasts$env.grid.tif, crs(cpcrw_rasts$env.grid_cpcrw06.tif), method = "near")
plot(env.grid_proj)


env.grid_proj06 <- project(cpcrw_rasts$env.grid_cpcrw06.tif, crs(cpcrw_rasts$env.grid.tif), method = "near")
plot(env.grid_proj06)



above_tst_crop_proj <- project(above_tst_crop, crs(cpcrw_rasts$env.grid.tif), method = "near")
plot(above_tst_crop_proj)