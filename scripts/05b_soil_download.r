library(terra)
library(here)

# Downloads soil property tiles from ISRIC SoilGrids for each landscape via
# the WCS API. Requests are scoped to the buffered landscape extent so only
# relevant tiles are downloaded — no global raster required.
#
# Variables downloaded:
#   sand, silt, clay — SoilGrids V2.0, all 6 standard depth layers
#   depth (BDTICM)   — SoilGrids V1.0, depth to bedrock (cm), single layer
#
# Raw tiles are saved to supporting_data/soils/<var>/ for each landscape.
# Processing (depth-weighted aggregation, reprojection) is handled separately.
#
# Note on geodata::soil_world(): this function supports all 6 depth layers but
# has no bounding box argument — it downloads the full global raster for every
# request. With 18 requests (3 vars x 6 depths) that would be impractical.
# The vsi = TRUE option avoids writing to disk but still reads the full global
# dataset into memory per crop. The WCS approach used here subsets server-side
# and transfers only the data needed, making it significantly more efficient.

# Sand/silt/clay — SoilGrids 2.0 (Poggio et al. 2021)
# DOI: https://doi.org/10.5194/soil-7-217-2021
# Sand: https://data.isric.org/geonetwork/srv/api/records/713396fa-1687-11ea-a7c0-a0481ca9e724
# Silt: https://data.isric.org/geonetwork/srv/api/records/713396fb-1687-11ea-a7c0-a0481ca9e724
# Clay: https://data.isric.org/geonetwork/srv/api/records/713396f7-1687-11ea-a7c0-a0481ca9e724
# https://files.isric.org/soilgrids/latest/data/
# Hengl 2017 data for sand/silt/clay not used here but available at:
# https://data.isric.org/geonetwork/srv/eng/catalog.search#/metadata/f9a3a4e0-27a8-4acc-861f-26c112699c3e
# https://files.isric.org/soilgrids/former/2017-03-10/data/
#
# Depth to bedrock (BDTICM) — SoilGrids 1.0 (Hengl et al. 2017)
# DOI: https://doi.org/10.1371/journal.pone.0169748
#   https://data.isric.org/geonetwork/srv/api/records/f36117ea-9be5-4afd-bb7d-7a3e77bf392a

dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])

soil_vars   <- c("sand", "silt", "clay")
depth_layers <- c("0-5cm_mean", "5-15cm_mean", "15-30cm_mean",
                  "30-60cm_mean", "60-100cm_mean", "100-200cm_mean")

# Build a SoilGrids V2.0 WCS URL for a given variable, depth layer, and bbox
# Poggio et al. (2020) DOI: https://doi.org/10.5194/soil-7-217-2021
# Hengl et al. (2017) DOI: 10.1371/journal.pone.0169748
wcs_url <- function(var, layer, bbox) {
  # bbox: named numeric vector with elements xmin, xmax, ymin, ymax (WGS84)
  paste0(
    "https://maps.isric.org/mapserv?map=/map/", var, ".map",
    "&SERVICE=WCS&VERSION=2.0.1&REQUEST=GetCoverage",
    "&COVERAGEID=", var, "_", layer,
    "&FORMAT=image/tiff",
    "&SUBSET=long(", bbox["xmin"], ",", bbox["xmax"], ")",
    "&SUBSET=lat(",  bbox["ymin"], ",", bbox["ymax"], ")",
    "&SUBSETTINGCRS=http://www.opengis.net/def/crs/EPSG/0/4326"
  )
}

# BDTICM (absolute depth to bedrock, cm) — SoilGrids V1.0 (Hengl et al. 2017)
# Served as a single global GeoTIFF; streamed via /vsicurl/ and cropped per
# landscape to avoid downloading the full ~1GB file.
# Source: https://files.isric.org/soilgrids/former/2017-03-10/data/BDTICM_M_250m_ll.tif
bdticm_url <- "/vsicurl/https://files.isric.org/soilgrids/former/2017-03-10/data/BDTICM_M_250m_ll.tif"

download_soil <- function(landscape_name) {

  message("Processing: ", landscape_name)

  env_file <- list.files(here(landscape_name, "gis"),
                         pattern = "env.grid.tif$", full.names = TRUE)
  env_grid     <- rast(env_file)
  env_buffered <- terra::buffer(as.polygons(env_grid, extent = TRUE), width = 4000)

  # Project buffered polygon to WGS84 — used both for WCS bbox strings and
  # for cropping the BDTICM raster via /vsicurl/
  env_buffered_wgs84 <- project(env_buffered, "EPSG:4326")
  bbox_wgs84 <- as.vector(ext(env_buffered_wgs84))
  names(bbox_wgs84) <- c("xmin", "xmax", "ymin", "ymax")

  # --- sand / silt / clay: 6 depth layers each ---
  for (var in soil_vars) {
    outdir <- here(landscape_name, "supporting_data", "soils", var)
    dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

    for (layer in depth_layers) {
      out_file <- file.path(outdir, paste0(var, "_", layer, ".tif"))

      if (file.exists(out_file)) {
        message("  ", var, " ", layer, " already exists, skipping.")
        next
      }

      url <- wcs_url(var, layer, bbox_wgs84)
      tmp <- tempfile(fileext = ".tif")
      tryCatch({
        download.file(url, destfile = tmp, mode = "wb", quiet = TRUE)
        file.copy(tmp, out_file)
        message("  Downloaded: ", var, " ", layer)
      }, error = function(e) {
        warning("  Failed: ", var, " ", layer, " — ", conditionMessage(e))
      }, finally = {
        unlink(tmp)
      })
    }
  }

  # --- depth to bedrock (BDTICM): streamed via /vsicurl/, cropped per landscape ---
  depth_dir  <- here(landscape_name, "supporting_data", "soils", "depth")
  depth_file <- file.path(depth_dir, "bdticm.tif")
  dir.create(depth_dir, recursive = TRUE, showWarnings = FALSE)

  if (file.exists(depth_file)) {
    message("  depth already exists, skipping.")
  } else {
    tryCatch({
      depth_crop <- crop(rast(bdticm_url), ext(env_buffered_wgs84))
      writeRaster(depth_crop, depth_file, overwrite = TRUE)
      message("  Downloaded: depth (BDTICM)")
    }, error = function(e) {
      warning("  Failed: depth (BDTICM) — ", conditionMessage(e))
    })
  }
}

#--------------- Run the function ---------------#

lapply(landscape_names, download_soil)

# cpcrw_sand1 <- rast("D:/quinn/GitHub/landscape_init_ak_can/landscape_alaska_landscape_01/supporting_data/soils/sand/sand_0-5cm_mean.tif")
# plot(cpcrw_sand1)

# # Check buffer
# cpcrw_sand1_proj_check <- project(cpcrw_sand1, crs(env_grid))
# plot(cpcrw_sand1_proj_check)
# plot(env_grid, add = TRUE)

# # check crop
# cpcrw_sand1_proj <- project(cpcrw_sand1, env_grid) |>
#   mask(env_grid)
# plot(cpcrw_sand1_proj)

# # check against files in Z
# soil_files <- list.files(
#   "//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/soils/ak",
#   full.names = TRUE)
# soil_names <- sub("_ak\\.tif$", "", basename(soil_files))
# soil_rast <- lapply(soil_files, terra::rast)
# names(soil_rast) <- soil_names

# soil_rast <- Map(\(r, nm) {
#   nnm <- paste0(nm, "_mean")
#   names(r) <- nnm
#   r
# }, soil_rast, soil_names)

# # Looks good so far but need to check conversions and values
# soil_rast_proj <- lapply(soil_rast, project, y = env_grid, method = "bilinear")
# sand_mean_mask <- soil_rast_proj$sand |> mask(env_grid)
# plot(sand_mean_mask)
# plot(cpcrw_sand1_proj)
# plot(soil_rast_proj$sand)
# plot(cpcrw_sand1_proj, add = TRUE)

# # Depth looks good but has been clipped to 200cm in the file on Z
# cpcrw_depth <- rast("D:/quinn/GitHub/landscape_init_ak_can/landscape_alaska_landscape_01/supporting_data/soils/depth/bdticm.tif")
# plot(cpcrw_depth)
# cpcrw_depth_proj <- project(cpcrw_depth, env_grid) |>
#   mask(env_grid)
# plot(cpcrw_depth_proj)
# plot(ifel(is.na(cpcrw_depth_proj), 1, NA), col = "black")

# cpcrw_depth2 <- cpcrw_depth_proj
# cpcrw_depth2 <- ifel(cpcrw_depth2 > 200, 200, cpcrw_depth2)
# plot(cpcrw_depth2)

# ak_soil_depth <- rast("Z:/project_data/na_boreal/data_sets/soils/ak/depth_ak.tif")
# glob_soil_depth <- rast("Z:/project_data/na_boreal/data_sets/soils/depth_soil_grids_1.tif")


# sand_depth_mask <- soil_rast_proj$depth |> mask(env_grid)
# plot(sand_depth_mask)
