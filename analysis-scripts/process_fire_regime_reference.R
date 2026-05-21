library(DBI)
library(RSQLite)
library(dplyr)
library(terra)

#------------------------------------------------------------------------------#
# Reference script for comparing Sections 5 & 6 of process_fire_regime.R.
# Follows the original Rmd (fire-regime_script-5_09-30-2022.Rmd) as closely
# as possible with two changes only:
#   1. Paths updated to local test data.
#   2. Deprecated sp/raster/rgdal/rgeos replaced with terra equivalents.
# No CLI args; no replicate loop (test data is a single replicate).
# Outputs to workflow-output/fire_regime_comparison/ for manual CSV diff.
#------------------------------------------------------------------------------#

sqlite_path   <- "Z:/personal_storage/quinn_storage/NorEsm2-MMssp126_dbh2.5_yr_31_iLand2.0/rep_3/NorEsm2-MMssp126_dbh2.5_yr_31_iLand2.0_3.sqlite"
env_grid_path <- "Z:/personal_storage/quinn_storage/landscape_init_ak_can/landscape_alaska_01/gis/env.grid.tif"
dsn           <- "//10.60.2.10/FF_Lab/project_data/na_boreal/sensitivity_analysis/data/historic_fire/raw data/fire"
output_dir    <- "Z:/personal_storage/quinn_storage/landscape_init_ak_can/workflow-output/fire_regime_comparison"
ak_grid_dir   <- file.path(output_dir, "ak_fire_grid")

dir.create(output_dir,  recursive = TRUE, showWarnings = FALSE)
dir.create(ak_grid_dir, recursive = TRUE, showWarnings = FALSE)

cat("--- process_fire_regime_reference ---\n",
    "start time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

#------------------------------------------------------------------------------#
# Load iLand fire table (single replicate — no replicate column added)
# Equivalent to original Rmd chunk lines 156–180.
#------------------------------------------------------------------------------#
db   <- DBI::dbConnect(RSQLite::SQLite(), dbname = sqlite_path)
fire <- DBI::dbReadTable(db, "fire")
DBI::dbDisconnect(db)

fire         <- fire[fire$area_m2 > 0, ]
fire$area_ha <- fire$area_m2 / 10000

env_grid          <- terra::rast(env_grid_path)
landscape_area_ha <- sum(!is.na(terra::values(env_grid)))

cat("landscape area (ha):", landscape_area_ha, "\n")
cat("Fire events loaded:", nrow(fire), "\n")
cat("Year range:", paste(range(fire$year), collapse = " - "), "\n\n")

#------------------------------------------------------------------------------#
# Section 2: Load historical AK fire perimeters and clip to landscape extent.
# Original: readOGR + raster::area → terra::vect + terra::expanse.
#------------------------------------------------------------------------------#
histfire          <- terra::vect(file.path(dsn, "AK_fire_location_polygons.shp"))
histfire$area_ha  <- histfire$Shape_Area / 10000
histfire$FIREYEAR <- as.numeric(histfire$FIREYEAR)
histfire          <- terra::project(histfire, terra::crs(env_grid))

cat("Historical fire polygons loaded:", nrow(histfire), "\n")
cat("Fire year range:", paste(range(histfire$FIREYEAR, na.rm = TRUE), collapse = " - "), "\n\n")

landscape_poly <- terra::as.polygons(
  terra::ifel(!is.na(env_grid), 1L, NA),
  dissolve = TRUE
)
terra::crs(landscape_poly) <- terra::crs(env_grid)

histfire_clip              <- terra::intersect(histfire, landscape_poly)
histfire_clip$clip_area_ha <- terra::expanse(histfire_clip, unit = "ha")

cat("Fire polygons clipped to landscape:", nrow(histfire_clip), "\n\n")

#------------------------------------------------------------------------------#
# Section 3: Observed FRP.
# Original: lines 240–265.
#------------------------------------------------------------------------------#
first_year   <- 1980
last_year    <- max(histfire$FIREYEAR, na.rm = TRUE)
frp_numyears <- (last_year - first_year) + 1

histfire_clip <- histfire_clip[
  !is.na(histfire_clip$FIREYEAR) &
  histfire_clip$FIREYEAR >= first_year &
  histfire_clip$FIREYEAR <= last_year, ]

if (nrow(histfire_clip) == 0) {
  warning("No historical fire polygons in landscape for ", first_year, "-", last_year)
  hist_frp         <- NA_real_
  hist_firesize    <- NA_real_
  sd_hist_firesize <- NA_real_
  hist_firefreq    <- NA_real_
} else {
  hist_frp         <- round(frp_numyears / (sum(histfire_clip$clip_area_ha) / landscape_area_ha), 0)
  hist_firesize    <- mean(histfire_clip$clip_area_ha)
  sd_hist_firesize <- sd(histfire_clip$clip_area_ha)
  hist_firefreq    <- nrow(histfire_clip) / frp_numyears
}

cat("Historical fire period:", first_year, "-", last_year, "(", frp_numyears, "years)\n")
cat("Historical FRP:        ", hist_frp, "years\n")
cat("Mean historical size:  ", round(hist_firesize, 0), "ha\n")
cat("Historical fire freq:  ", round(hist_firefreq, 2), "fires/year\n\n")

#------------------------------------------------------------------------------#
# Section 4: No replicate selection — single replicate in test data.
# Compute fire_summary for the comparison table output.
#------------------------------------------------------------------------------#
n_sim_years  <- max(fire$year) - min(fire$year) + 1
fire_summary <- data.frame(
  iland_firesize = mean(fire$area_ha),
  sd_firesize    = sd(fire$area_ha),
  iland_firefreq = nrow(fire) / n_sim_years
)
fire_best <- fire

cat("Simulation years:", n_sim_years, "\n")
cat("Mean iLand fire size:  ", round(fire_summary$iland_firesize, 0), "ha\n")
cat("iLand fire frequency:  ", round(fire_summary$iland_firefreq, 2), "fires/year\n\n")

#------------------------------------------------------------------------------#
# Section 5: AK-wide grid FRP.
# Original: per-cell gIntersection loop with sp/rgeos — replaced with
# terra::intersect (vectorised). Grid built with terra::rast + as.polygons
# instead of manual SpatialPolygons loop. All other logic unchanged.
# Original Rmd lines 276–424.
#------------------------------------------------------------------------------#
run_anew <- !file.exists(file.path(ak_grid_dir, "frp_raster.tif"))

if (run_anew) {
  cat("Computing AK grid FRP (run_anew = TRUE)...\n")

  ak_poly <- terra::project(
    terra::vect(file.path(dsn, "AK_polygon.shp")),
    terra::crs(env_grid)
  )

  histfire_yr  <- histfire[!is.na(histfire$FIREYEAR) &
                            histfire$FIREYEAR >= first_year &
                            histfire$FIREYEAR <= last_year, ]
  histfire_yr  <- terra::makeValid(histfire_yr)
  histfire_agg <- terra::aggregate(histfire_yr, by = "FIREYEAR", dissolve = TRUE)

  ak_grid_rast       <- terra::rast(terra::ext(histfire),
                                    resolution = c(25500, 23900),
                                    crs = terra::crs(env_grid))
  ak_grid_rast[]     <- seq_len(terra::ncell(ak_grid_rast))
  ak_grid_polys      <- terra::as.polygons(ak_grid_rast)
  names(ak_grid_polys)[1] <- "cell_id"
  ak_grid_polys$AREA_ha   <- terra::expanse(ak_grid_polys, unit = "ha")

  land_mask     <- terra::relate(ak_grid_polys, ak_poly, relation = "intersects")[, 1]
  ak_grid_polys <- ak_grid_polys[land_mask, ]

  fire_x_grid              <- terra::intersect(ak_grid_polys, histfire_agg)
  fire_x_grid$clip_area_ha <- terra::expanse(fire_x_grid, unit = "ha")

  cell_stats <- as.data.frame(fire_x_grid)[, c("cell_id", "clip_area_ha")] |>
    group_by(cell_id) |>
    summarize(
      total_burned_ha = sum(clip_area_ha),
      num_fires       = n(),
      mean_firesize   = mean(clip_area_ha),
      .groups = "drop"
    )

  grid_df <- dplyr::left_join(as.data.frame(ak_grid_polys), cell_stats, by = "cell_id") |>
    mutate(
      FRP            = round(frp_numyears / (total_burned_ha / AREA_ha), 0),
      FRP            = ifelse(!is.na(FRP) & FRP > 10000, NA, FRP),
      FIRE_FREQ      = ifelse(is.na(num_fires) | num_fires == 0, NA,
                              frp_numyears / num_fires),
      MEAN_FIRE_SIZE = mean_firesize
    )

  ak_grid_polys$FRP            <- grid_df$FRP
  ak_grid_polys$MEAN_FIRE_SIZE <- grid_df$MEAN_FIRE_SIZE
  ak_grid_polys$FIRE_FREQ      <- grid_df$FIRE_FREQ

  terra::writeRaster(terra::rasterize(ak_grid_polys, ak_grid_rast, field = "FRP"),
                     file.path(ak_grid_dir, "frp_raster.tif"),      overwrite = TRUE)
  terra::writeRaster(terra::rasterize(ak_grid_polys, ak_grid_rast, field = "MEAN_FIRE_SIZE"),
                     file.path(ak_grid_dir, "firesize_raster.tif"), overwrite = TRUE)
  terra::writeRaster(terra::rasterize(ak_grid_polys, ak_grid_rast, field = "FIRE_FREQ"),
                     file.path(ak_grid_dir, "firefreq_raster.tif"), overwrite = TRUE)

  cat("AK grid rasters written to:", ak_grid_dir, "\n\n")
} else {
  cat("AK grid rasters already exist — loading from cache.\n\n")
}

frp_rast      <- terra::rast(file.path(ak_grid_dir, "frp_raster.tif"))
firesize_rast <- terra::rast(file.path(ak_grid_dir, "firesize_raster.tif"))
firefreq_rast <- terra::rast(file.path(ak_grid_dir, "firefreq_raster.tif"))

#------------------------------------------------------------------------------#
# Section 6: Rolling FRP — original Rmd for loop (lines 494–508).
# Only substitutions: replicate==6 → no filter (single rep);
# cpcrw_area → landscape_area_ha. Loop structure unchanged.
#------------------------------------------------------------------------------#
first_ilandyear <- min(fire_best$year) + frp_numyears
last_ilandyear  <- max(fire_best$year)

if (first_ilandyear > last_ilandyear) {
  warning("frp_numyears (", frp_numyears, ") exceeds simulation length (",
          n_sim_years, " years) — rolling FRP cannot be computed. Skipping.")
  rolling_frp_df <- data.frame(year = integer(0), iland_frp = numeric(0))
} else {
  iland_frp <- rep(NA_real_, last_ilandyear - first_ilandyear + 1)
  count     <- 1
  for (yr in first_ilandyear:last_ilandyear) {
    years_to_eval    <- (yr - frp_numyears + 1):yr
    area_burned      <- sum(fire_best$area_ha[fire_best$year %in% years_to_eval])
    iland_frp[count] <- round(frp_numyears / (area_burned / landscape_area_ha), 0)
    count            <- count + 1
  }
  rolling_frp_df <- data.frame(year = first_ilandyear:last_ilandyear, iland_frp)
}

cat("Rolling FRP (single replicate):\n")
print(rolling_frp_df)
cat("\nFinal rolling FRP:", tail(rolling_frp_df$iland_frp, 1), "years\n\n")

write.csv(rolling_frp_df,
          file.path(output_dir, "rolling_frp.csv"),
          row.names = FALSE)

# Per-year fire summary (original Rmd lines 649–651).
# prop_n_died / prop_ba_died as aggregate proportions per year.
annual_fire <- fire_best |>
  group_by(year) |>
  summarize(
    total_area_ha = sum(area_ha),
    prop_n_died   = {
      d <- sum(n_trees, na.rm = TRUE)
      if (d == 0) 0 else sum(n_trees_died, na.rm = TRUE) / d
    },
    prop_ba_died  = {
      d <- sum(basalArea_total, na.rm = TRUE)
      if (d == 0) 0 else sum(basalArea_died, na.rm = TRUE) / d
    },
    .groups = "drop"
  )

write.csv(annual_fire,
          file.path(output_dir, "annual_fire_summary.csv"),
          row.names = FALSE)

final_iland_frp <- if (nrow(rolling_frp_df) > 0) tail(rolling_frp_df$iland_frp, 1) else NA_real_

comparison_df <- data.frame(
  metric    = c("frp_years", "mean_firesize_ha", "firefreq_fires_per_year"),
  observed  = c(hist_frp,    hist_firesize,       hist_firefreq),
  simulated = c(final_iland_frp,
                fire_summary$iland_firesize,
                fire_summary$iland_firefreq)
)

cat("Fire comparison (observed vs simulated):\n")
print(comparison_df)
cat("\n")

write.csv(comparison_df,
          file.path(output_dir, "fire_comparison.csv"),
          row.names = FALSE)

cat("Outputs written to:", output_dir, "\n")
cat("  rolling_frp.csv\n")
cat("  annual_fire_summary.csv\n")
cat("  fire_comparison.csv\n")
cat("\nDone:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
