library(terra)
library(here)

# Processes raw SoilGrids tiles downloaded in step 05b for each landscape.
# For sand, silt, and clay: stacks the 6 depth layers, computes a
# thickness-weighted mean, converts from g/kg to %, reprojects to the 100m
# env.grid, and rounds to integer. Sand and clay are rounded as proportions of
# the true total; silt is derived as the exact residual (100 - sand - clay) so
# that sand + silt + clay = 100 exactly for every cell.
# For depth to bedrock (BDTICM): reprojects to the env.grid with no unit
# conversion (already in cm).
# Outputs are saved to supporting_data/soils_processed/ per landscape, ready
# for use in step 10.

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
    # result <- round(result)
  })
  names(processed) <- soil_vars

  # Fill cells where all three textures are 0 (areas with no SoilGrids data)
  # by interpolating from the surrounding valid cells.
  zero_mask <- (processed$sand + processed$silt + processed$clay) == 0
  for (v in soil_vars) {
    r <- ifel(zero_mask, NA, processed[[v]])
    processed[[v]] <- terra::focal(r, w = 3, fun = "mean", na.rm = TRUE, na.policy = "only")
  }

  # Normalise to proportions of the actual total, then derive silt as the exact
  # residual. This guarantees sand + silt + clay = 100 regardless of how far the
  # depth-weighted sum deviates from 100 before rounding.
  # ifel(total > 0, ...) guards against any remaining cells with no neighbour data.
  total <- processed$sand + processed$silt + processed$clay
  processed$sand <- ifel(total > 0, round(processed$sand / total * 100), 0)
  processed$clay <- ifel(total > 0, round(processed$clay / total * 100), 0)
  processed$silt <- ifel(total > 0, 100 - processed$sand - processed$clay, 0)

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
              overwrite = TRUE, datatype = "INT2S")

  message("  Done: ", landscape_name)
}

#--------------- Run the function ---------------#

dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])

lapply(landscape_names, process_soil)
