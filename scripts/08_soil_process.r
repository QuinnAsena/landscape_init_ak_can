library(terra)
library(here)

# Processes raw SoilGrids tiles downloaded in step 05b for each landscape.
# For sand, silt, and clay: stacks the 6 depth layers, computes a
# thickness-weighted mean, converts from g/kg to %, reprojects to the 100m
# env.grid, and rounds to integer. Silt is adjusted by ±1 to correct any
# rounding artefact so that sand + silt + clay = 100.
# For depth to bedrock (BDTICM): reprojects to the env.grid with no unit
# conversion (already in cm).
# Outputs are saved to supporting_data/soils_processed/ per landscape, ready
# for use in step 10.
#
# Note: 10_env.file_create.r currently loads soil rasters from the network
# drive. It will need updating to load from supporting_data/soils_processed/
# and strip .tif (not _ak.tif) from filenames to derive layer names.

# Depth layer names in correct order — do not use list.files() + sort() as
# alphabetical order is wrong (e.g. "100-200cm" sorts before "15-30cm")
depth_layers <- c("0-5cm_mean", "5-15cm_mean", "15-30cm_mean",
                  "30-60cm_mean", "60-100cm_mean", "100-200cm_mean")

# Thickness of each depth layer (cm) — used as weights for the weighted mean
layer_weights <- c(5, 10, 15, 30, 40, 100)

soil_vars <- c("sand", "silt", "clay")

process_soil <- function(landscape_name) {

  message("Processing: ", landscape_name)

  env_file <- list.files(here(landscape_name, "gis"),
                         pattern = "env.grid.tif$", full.names = TRUE)
  env_grid <- rast(env_file)

  out_dir <- here(landscape_name, "supporting_data", "soils_processed")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # --- sand / silt / clay ---
  processed <- lapply(soil_vars, function(var) {
    # Build file paths in explicit depth order
    layer_files <- file.path(
      here(landscape_name, "supporting_data", "soils", var),
      paste0(var, "_", depth_layers, ".tif")
    )
    # Stack all 6 depth layers and compute thickness-weighted mean
    soil_stack <- rast(layer_files)
    soil_wmean <- terra::weighted.mean(soil_stack, w = layer_weights, na.rm = TRUE)
    soil_wmean <- soil_wmean / 10
    soil_wmean <- subst(soil_wmean, NA, 0)
    # SoilGrids V2.0 values are in g/kg — divide by 10 to convert to %
    # Reproject to env.grid, crop and mask to landscape extent
    result <- project(soil_wmean, env_grid, method = "bilinear") |>
      crop(env_grid) |>
      mask(env_grid)
    result <- round(result)
  })
  names(processed) <- soil_vars

  # Adjust silt by ±1 to correct rounding artefacts so sand + silt + clay = 100
  total <- processed$sand + processed$silt + processed$clay
  processed$silt <- ifel(total == 101, processed$silt - 1,
                     ifel(total == 99,  processed$silt + 1, processed$silt))

  for (var in soil_vars) {
    names(processed[[var]]) <- var  # layer name used by 10_env.file_create.r
    writeRaster(processed[[var]],
                file.path(out_dir, paste0(var, ".tif")),
                overwrite = TRUE, datatype = "INT2S")
  }

  # --- depth to bedrock (BDTICM) ---
  depth_rast <- rast(here(landscape_name, "supporting_data", "soils", "depth", "bdticm.tif"))
  depth_processed <- project(depth_rast, env_grid, method = "bilinear") |>
    crop(env_grid) |>
    mask(env_grid)
  names(depth_processed) <- "depth"
  depth_processed <- ifel(depth_processed > 200, 200, depth_processed)
  depth_processed <- subst(depth_processed, NA, 0)
  writeRaster(depth_processed,
              file.path(out_dir, "depth.tif"),
              overwrite = TRUE)

  message("  Done: ", landscape_name)
}

#--------------- Run the function ---------------#

dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])

lapply(landscape_names, process_soil)
