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

# We are using the plot areas even though they already are the above lc data
landscapes_files <- list.files(
  path = "//10.60.2.10/FF_Lab/personal_storage/quinn_storage/ak_plot_areas",
  pattern = "\\.tif$", full.names = TRUE)

landscapes_files <- landscapes_files[order(as.integer(sub(".*?(\\d+)\\.tif$", "\\1", landscapes_files)))]
r1 <- rast(landscapes_files[1])
r6 <- rast(landscapes_files[6])
plot(r1)
plot(r6)
same.crs(r1, r6)
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


# Now we crop all 5 landscapes out of the vrt and save the rasters
vrt_lcp <- function(lcp_vrt, landscapes_file) {
  nm <- sub("_\\d+$", "", names(lcp_vrt)[1])
  lcp_nm <- file.path(paste0("landscape_", sub(".*?(\\d+)\\.tif$", "\\1", landscapes_file)))
  out <- file.path(here(), lcp_nm, nm)
  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  lcp_crop_area <- rast(landscapes_file)

  if (!same.crs(lcp_crop_area, lcp_vrt)) {
    stop("Check on crs")
  } else {
    cookie_cutter <- as.polygons(lcp_crop_area, crs = crs(lcp_crop_area), dissolve = TRUE)
  }
  # crop() output includes all cells rectangle, including cells not in study area
  vrt_crop <- crop(lcp_vrt, cookie_cutter) |>
    mask(cookie_cutter)
  
  writeRaster(vrt_crop, file.path(out, paste0(nm, ".tif")), overwrite = TRUE, datatype = "INT4S")
}

lapply(landscapes_files, vrt_lcp, lcp_vrt = above_lc_vrt)
lapply(landscapes_files, vrt_lcp, lcp_vrt = water_vrt)

tst <- rast("D:/quinn/GitHub/landscape_init_ak_can/landscape_06/ABoVE_LandCover/ABoVE_LandCover.tif")
plot(tst)

tst2 <- rast("D:/quinn/GitHub/landscape_init_ak_can/landscape_01/ABoVE_Water/ABoVE_Water.tif")
plot(tst2)
