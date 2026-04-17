library(terra)
library(here)

# ---------- Read data ---------- #
# ABoVE study domain: defines the spatial reference grid
# https://www.earthdata.nasa.gov/data/catalog/ornl-cloud-above-reference-grid-v2-1527-2.1

# ABoVE landcover: annual land cover classifications (1984-2014), 1 tif per tile
# https://www.earthdata.nasa.gov/data/catalog/ornl-cloud-annual-landcover-above-1691-1

# ABoVE surface water: decadal surface water maps (1991-2011), 1 tif per tile per decade
# https://www.earthdata.nasa.gov/data/catalog/ornl-cloud-decadal-water-maps-1324-1.1

above_study_domain_file <- list.files(
  "//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/ABoVE_reference_grid_v2_1527/data",
  pattern = "\\.tif$", full.names = TRUE)

above_study_domain <- rast(above_study_domain_file)
plot(above_study_domain)
crs(above_study_domain)

# Annual land cover: 1 tif per tile, 31 layers (1 per year, 1984-2014)
above_lc_files <- list.files(
  "//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/Annual_Landcover_ABoVE_1691/data",
  pattern = "\\.tif$", full.names = TRUE)
# Filter out the simplified 10-class version; keep the full 15-class product
above_lc_files <- above_lc_files[!grepl(pattern = "Simplified", above_lc_files)]

# Surface water: 1 tif per tile per decade — split and combined into a VRT below
above_water_files <- list.files(
  "//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/Decadal_Water_Maps_1324/data",
  pattern = "\\.tif$", full.names = TRUE)
# Filter out Quality Assurance (QA) files; keep only the water data tiles
above_water_files <- above_water_files[!grepl(pattern = "QA", above_water_files)]

# Load up Lora's selected landscapes
landscapes_poly <- vect(here("data", "landscape_selection", "final_plots_above_proj.shp"))
plot(above_study_domain)
plot(landscapes_poly, add = TRUE, col = "red")
# ---------- check crs ---------- #

r_lc <- rast(above_lc_files[1])
r_sw <- rast(above_water_files[1])
same.crs(r_lc, r_sw)
same.crs(r_lc, landscapes_poly)
same.crs(r_lc, above_study_domain)

# Stitch cpcrw on
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
plot(above_study_domain)
plot(landscapes_poly, add = TRUE, col = "red")

# Grouped numbering by region
is_alaska <- grepl("ALASKA", landscapes_poly$ecoregion, ignore.case = TRUE)
alaska_idx <- seq_len(sum(is_alaska))
canada_idx <- seq_len(sum(!is_alaska))

landscapes_poly$landscape_id <- NA
landscapes_poly$landscape_id[is_alaska]  <- paste0("alaska_", sprintf("%02d", alaska_idx))
landscapes_poly$landscape_id[!is_alaska] <- paste0("canada_", sprintf("%02d", canada_idx))

# Create vrt once outside function
above_lc_vrt <- vrt(above_lc_files, set_names = TRUE)
# set_names pulls layer names from the first tile only, which are tile-specific —
# strip the tile prefix so layer names reflect year only (e.g. "ABoVE_LandCover_2000")
names(above_lc_vrt) <- gsub("Bh01v02_", "", names(above_lc_vrt))

# Group water files by decade, build a VRT per decade, then combine into a
# single multi-layer raster with 1 layer per decade (1991, 2001, 2011)
above_water_file_names <- basename(above_water_files)
decades <- sub(".*_(\\d{4})\\.tif$", "\\1", above_water_file_names)
above_water_decade <- split(above_water_files, decades)

water_vrt_decade <- lapply(above_water_decade, \(r) {
  v <- vrt(r, set_names = TRUE) # mosaic all tiles for this decade into a VRT
  names(v) <- gsub("h00v00_", "", names(v))
  v
})
# Stack the per-decade VRTs into a single raster (1 layer per decade)
water_vrt <- Reduce(c, water_vrt_decade)


# ---------- function to crop and mask landscape ---------- #
crop_lcp <- function(lcp_vrt, poly) {
  lcp <- file.path(paste0("landscape_", poly$landscape_id), "supporting_data")
  nm <- sub("_\\d+$", "", names(lcp_vrt)[1])
  out <- file.path(here(), lcp, nm)
  dir.create(out, recursive = TRUE)

  if (!same.crs(lcp_vrt, poly)) {
    warning("Check on crs in: ", lcp, "\nprojecting to ", crs(lcp_vrt))
    poly <- project(poly, crs(lcp_vrt))
  }
  # Replace outside-landscape NAs with -1 before masking so they can be
  # distinguished from genuine NA values that exist within the landscape boundary
  vrt_crop_full <- suppressWarnings(crop(lcp_vrt, poly))
  vrt_crop_full <- subst(vrt_crop_full, NA, -1)
  vrt_crop <- suppressWarnings(crop(vrt_crop_full, poly, mask = TRUE))

  writeRaster(vrt_crop, file.path(out, paste0(nm, ".tif")), overwrite = TRUE, datatype = "INT4S")
}

# ---------- crop and mask ABoVE data to each landscape polygon ---------- #

lapply(
  seq_len(nrow(landscapes_poly)),
  \(i) crop_lcp(above_lc_vrt, landscapes_poly[i, ])
)

lapply(
  seq_len(nrow(landscapes_poly)),
  \(i) crop_lcp(water_vrt, landscapes_poly[i, ])
)
