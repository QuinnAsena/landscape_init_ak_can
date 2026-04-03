library(terra)
library(geodata)
library(here)

# Downloads soil property rasters from ISRIC SoilGrids for each landscape.
# clay, sand, and silt (0-5cm depth mean, ~250m resolution) are downloaded via
# geodata::soil_world(), which caches the global raster locally on first call.
# Depth to bedrock (BDRICM, cm) is streamed directly from the SoilGrids COG
# via /vsicurl/ — no full download required.
# A 4000m buffer is applied to ensure full coverage of landscape border cells.
# Outputs are saved to supporting_data/soils/ within each landscape directory
# and can replace the network drive rasters used in step 10.

# NOTE: verify the BDRICM URL below before running — SoilGrids COG paths
# can change between dataset versions.

dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])

# Soil texture variables available via geodata::soil_world()
soil_vars <- c("clay", "sand", "silt")

# Shared cache directory for geodata downloads — avoids re-downloading the
# global raster for each landscape
soil_cache <- here("data", "soils", "cache")
dir.create(soil_cache, recursive = TRUE, showWarnings = FALSE)

# Depth to bedrock streamed as a cloud-optimised GeoTIFF (no full download)
bdricm_url <- "/vsicurl/https://files.isric.org/soilgrids/latest/data/bdricm/BDRICM_M_250m_ll.tif"

crop_soil <- function(landscape_name) {

  outdir <- here(landscape_name, "supporting_data", "soils")
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

  env_file <- list.files(here(landscape_name, "gis"),
                         pattern = "env.grid.tif$", full.names = TRUE)
  env_grid     <- rast(env_file)
  env_buffered <- terra::buffer(as.polygons(env_grid, extent = TRUE), width = 4000)

  # SoilGrids data are in WGS84 — project the buffered extent for cropping
  # before reprojecting back to the landscape CRS
  env_ext_wgs84 <- project(ext(env_buffered), from = crs(env_grid), to = "EPSG:4326")

  # Download (or load from cache) and crop texture variables
  for (var in soil_vars) {
    out_file <- file.path(outdir, paste0(var, ".tif"))
    if (file.exists(out_file)) {
      message(landscape_name, ": ", var, " already exists, skipping.")
      next
    }
    soil_dl <- geodata::soil_world(var = var, depth = 5, stat = "mean",
                                   path = soil_cache)
    soil_crop <- crop(soil_dl, ext(env_ext_wgs84)) |>
      project(crs(env_grid)) |>
      crop(env_buffered) |>
      mask(env_buffered)
    writeRaster(soil_crop, out_file, overwrite = TRUE)
    message(landscape_name, ": ", var, " done.")
  }

  # Depth to bedrock — stream and crop without downloading the global file
  depth_file <- file.path(outdir, "depth.tif")
  if (file.exists(depth_file)) {
    message(landscape_name, ": depth already exists, skipping.")
  } else {
    depth_crop <- crop(rast(bdricm_url), ext(env_ext_wgs84)) |>
      project(crs(env_grid)) |>
      crop(env_buffered) |>
      mask(env_buffered)
    writeRaster(depth_crop, depth_file, overwrite = TRUE)
    message(landscape_name, ": depth done.")
  }
}

#--------------- Run the function ---------------#

lapply(landscape_names, crop_soil)
