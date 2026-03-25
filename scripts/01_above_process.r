library(terra)
library(here)

r <- terra::rast("Z:/project_data/downscaling/Landscapes/Downscaled NorESM2-MM/ssp126/tasmax/NorESM2-MM-ssp126-tasmax-1950.nc", lyrs = 1)
writeRaster(r, file.path(here("data"), paste0("NorESM2-MM-ssp126-tasmax-1950.tif")), overwrite = TRUE, datatype = "INT4S")



# ---------- Read data ---------- #
# ABoVE study domain
# ABoVE landcover
# ABoVE surface water

above_study_domain_file <- list.files(
  "//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/ABoVE_reference_grid_v2_1527/data",
  pattern = "\\.tif$", full.names = TRUE)

above_study_domain <- rast(above_study_domain_file)
plot(above_study_domain)
crs(above_study_domain)

# Above landcover has 1 tif per tile with 31 lyrs (1 per yr)
# https://www.earthdata.nasa.gov/data/catalog/ornl-cloud-annual-landcover-above-1691-1
above_lc_files <- list.files(
  "//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/Annual_Landcover_ABoVE_1691/data",
  pattern = "\\.tif$", full.names = TRUE)
# Filter out 10 class
above_lc_files <- above_lc_files[!grepl(pattern = "Simplified", above_lc_files)]

# Above surface water files have a tif per tile per decade so we deal with that later
# https://www.earthdata.nasa.gov/data/catalog/ornl-cloud-decadal-water-maps-1324-1.1
above_water_files <- list.files(
  "//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/Decadal_Water_Maps_1324/data",
  pattern = "\\.tif$", full.names = TRUE)
# Filter out Quality Assurance
above_water_files <- above_water_files[!grepl(pattern = "QA", above_water_files)]

# Load up Lora's selected landscapes
landscapes_poly <- vect("//10.60.2.10/FF_Lab/project_data/na_boreal/Landscape building/Landscape selection/Selected plots/final_plots.shp")

# ---------- check crs ---------- #

r_lc <- rast(above_lc_files[1])
r_sw <- rast(above_water_files[1])
same.crs(r_lc, r_sw)
same.crs(r_lc, landscapes_poly)
same.crs(r_lc, above_study_domain)

landscapes_poly_proj <- project(landscapes_poly, crs(r_lc))
plot(landscapes_poly_proj)
plot(landscapes_poly_proj[1, ])
plot(landscapes_poly[1, ])

# Awkwardly stich cpcrw on
cpcrw <- rast(here("data", "cpcrw", "env.grid.tif"))
cpcrw_poly <- as.polygons(cpcrw, extent = TRUE) |>
  project(crs(landscapes_poly))
plot(cpcrw_poly)
same.crs(cpcrw_poly, landscapes_poly)

cpcrw_poly$ID            <- 1
cpcrw_poly$ecoregion     <- "ALASKA CPCRW"
cpcrw_poly$Propforest     <- NA
cpcrw_poly$Suppressio     <- NA

landscapes_poly <- rbind(cpcrw_poly, landscapes_poly)

# sequential numbering
# landscapes_poly$landscape_id <- ifelse(
#   grepl("ALASKA", landscapes_poly$ecoregion),
#   paste0("alaska_landscape_", sprintf("%02d", seq_len(nrow(landscapes_poly)))),
#   paste0("canada_landscape_", sprintf("%02d", seq_len(nrow(landscapes_poly))))
# )

# Grouped numbering. Not sure if I should be carrying through the original IDs
is_alaska <- grepl("ALASKA", landscapes_poly$ecoregion, ignore.case = TRUE)
alaska_idx <- seq_len(sum(is_alaska))
canada_idx <- seq_len(sum(!is_alaska))

landscapes_poly$landscape_id <- NA
landscapes_poly$landscape_id[is_alaska]  <- paste0("alaska_landscape_", sprintf("%02d", alaska_idx))
landscapes_poly$landscape_id[!is_alaska] <- paste0("canada_landscape_", sprintf("%02d", canada_idx))


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


# ---------- function to sort shit out ---------- #
crop_lcp <- function(lcp_vrt, poly) {
  lcp <- file.path(paste0("landscape_", poly$landscape_id), "supporting_data")
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

# ---------- apply sort-shit-out function to ABoVE data ---------- #

landscapes <- lapply(
  seq_len(nrow(landscapes_poly)),
  \(i) crop_lcp(above_lc_vrt, landscapes_poly[i, ])
)

landscapes <- lapply(
  seq_len(nrow(landscapes_poly)),
  \(i) crop_lcp(water_vrt, landscapes_poly[i, ])
)
