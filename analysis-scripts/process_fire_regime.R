library(DBI)
library(RSQLite)
library(dplyr)
library(terra)

args      <- commandArgs(TRUE)
landscape <- args[1]   # e.g. "landscape_alaska_01_1950-1980spinup"
treatment <- args[2]   # e.g. "NorEsm2-MMssp126_dbh2.5_onlysimfalse_yr_1_iLand2.1"

user       <- "qasena"
data_path  <- paste0("/glade/derecho/scratch/", user, "/output_ak_can/", landscape, "/")
output_dir <- file.path(data_path, "processed", treatment, "fire_regime")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cat(
  "--- process_fire_regime ---\n",
  "landscape:  ", landscape, "\n",
  "treatment:  ", treatment, "\n",
  "output_dir: ", output_dir, "\n",
  "start time: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n"
)

#------------------------------------------------------------------------------#
# Landscape area from env.grid (replaces hardcoded CPCRW 25500x23900m)
# Each 100m cell = 1 ha; count non-NA cells for the actual simulation footprint.
#------------------------------------------------------------------------------#
landscape_dir     <- sub("^(landscape_[^_]+_\\d+)_.*", "\\1", landscape)
env_path          <- paste0("/glade/work/qasena/landscape_init_ak_can/", landscape_dir, "/gis/env.grid.tif")
env_grid          <- terra::rast(env_path)
landscape_area_ha <- sum(!is.na(terra::values(env_grid)))

cat("landscape area (ha):", landscape_area_ha, "\n\n")

#------------------------------------------------------------------------------#
# Discover replicate directories and load fire table from each SQLite file.
# Replicates are inferred from directory names (rep_1, rep_2, ...) so the
# script works for any number of replicates without hardcoding.
#------------------------------------------------------------------------------#
rep_dirs <- list.dirs(file.path(data_path, treatment), recursive = FALSE, full.names = FALSE)
rep_nums  <- sort(as.integer(sub("rep_", "", grep("^rep_", rep_dirs, value = TRUE))))

if (length(rep_nums) == 0) stop("No replicate directories found in: ", file.path(data_path, treatment))

cat("Found replicates:", paste(rep_nums, collapse = ", "), "\n\n")

fire <- dplyr::bind_rows(lapply(rep_nums, function(rep) {
  input_file <- file.path(
    data_path, treatment,
    paste0("rep_", rep),
    paste0(treatment, "_", rep, ".sqlite")
  )
  if (!file.exists(input_file)) {
    warning("Input file not found: ", input_file)
    return(NULL)
  }
  db <- DBI::dbConnect(RSQLite::SQLite(), dbname = input_file)
  df <- DBI::dbReadTable(db, "fire")
  DBI::dbDisconnect(db)
  df$replicate <- rep
  df <- df |> filter(year >= 200)
  df
}))



#------------------------------------------------------------------------------#
      # Temporary files for testing
      fire <- DBI::dbConnect(RSQLite::SQLite(),
          dbname = "Z:/personal_storage/quinn_storage/NorEsm2-MMssp126_dbh2.5_yr_31_iLand2.0/rep_3/NorEsm2-MMssp126_dbh2.5_yr_31_iLand2.0_3.sqlite") |>
        DBI::dbReadTable("fire")
      env_grid <-terra::rast("Z:/personal_storage/quinn_storage/landscape_init_ak_can/landscape_alaska_01/gis/env.grid.tif")
      landscape_area_ha <- sum(!is.na(terra::values(env_grid)))
#------------------------------------------------------------------------------#



# Drop events where nothing burned (area_m2 == 0 rows are iLand no-fire records)
fire <- fire[fire$area_m2 > 0, ]
fire$area_ha <- fire$area_m2 / 10000

cat("Fire events loaded:", nrow(fire), "\n")
cat("Year range:        ", paste(range(fire$year), collapse = " – "), "\n")
cat("Replicates in data:", paste(sort(unique(fire$replicate)), collapse = ", "), "\n\n")

#------------------------------------------------------------------------------#
# Section 2: Load historical AK fire perimeters and clip to landscape extent.
# Replaces readOGR + raster::area() from original; uses terra::vect + expanse.
# DSN is a network drive path — update to HPC path before running on Derecho.
#------------------------------------------------------------------------------#
dsn      <- "/glade/work/qasena/landscape_init_ak_can/data/historic_fire/raw data/fire"
histfire <- terra::vect(file.path(dsn, "AK_fire_location_polygons.shp"))

histfire$area_ha  <- histfire$Shape_Area / 10000
histfire$FIREYEAR <- as.numeric(histfire$FIREYEAR)

# Reproject to env_grid CRS so all subsequent spatial operations share one CRS.
histfire <- terra::project(histfire, terra::crs(env_grid))

cat("Historical fire polygons loaded:", nrow(histfire), "\n")
cat("Fire year range:", paste(range(histfire$FIREYEAR, na.rm = TRUE), collapse = " – "), "\n\n")

# Clip historical perimeters to the landscape spatial extent.
# histfire is already in env_grid CRS so no intermediate reprojection is needed.

# Possible mismatch here because landscape footprint could be irregular (i.e., landscape 01 is a diamond within the square area)
landscape_poly <- terra::as.polygons(
  terra::ifel(!is.na(env_grid), 1L, NA),
  dissolve = TRUE
)
terra::crs(landscape_poly) <- terra::crs(env_grid)

histfire_clip              <- terra::intersect(histfire, landscape_poly)
histfire_clip$clip_area_ha <- terra::expanse(histfire_clip, unit = "ha")

cat("Fire polygons clipped to landscape:", nrow(histfire_clip), "\n\n")

#------------------------------------------------------------------------------#
# Section 3: Observed FRP for the landscape area.
# FRP = time (years) / (total burned area / area of interest).
# Period: 1980–present; pre-1980 data are less complete (perimeters >1000 ac only).
# frp_numyears and first_year are kept as named scalars — reused in Sections 5 & 6.
#------------------------------------------------------------------------------#
first_year   <- 1980
last_year    <- max(histfire$FIREYEAR, na.rm = TRUE)
frp_numyears <- (last_year - first_year) + 1

histfire_clip <- histfire_clip[
  !is.na(histfire_clip$FIREYEAR) &
  histfire_clip$FIREYEAR >= first_year &
  histfire_clip$FIREYEAR <= last_year, ]

if (nrow(histfire_clip) == 0) {
  warning("No historical fire polygons within landscape extent for ", first_year, "–", last_year,
          ". hist_frp will be NA.")
  hist_frp      <- NA_real_
  hist_firesize <- NA_real_
  sd_hist_firesize <- NA_real_
  hist_firefreq <- NA_real_
} else {
  hist_frp      <- round(frp_numyears / (sum(histfire_clip$clip_area_ha) / landscape_area_ha), 0)
  hist_firesize <- mean(histfire_clip$clip_area_ha)
  sd_hist_firesize <- sd(histfire_clip$clip_area_ha)
  hist_firefreq <- nrow(histfire_clip) / frp_numyears
}

cat("Historical fire period:     ", first_year, "–", last_year, "(", frp_numyears, "years)\n")
cat("Historical FRP (landscape): ", hist_frp, "years\n")
cat("Mean historical fire size:  ", round(hist_firesize, 0), "ha\n")
cat("Historical fire frequency:  ", round(hist_firefreq, 2), "fires/year\n\n")

#------------------------------------------------------------------------------#
# Section 4: Replicate selection.
# Summarise iLand fire stats over the last 100 simulation years per replicate,
# compare to observed (hist_firesize, hist_firefreq) via relative difference,
# and select the replicate with the smallest combined absolute difference.
# Original hardcoded year > 200 and observed values; both are now computed.
#------------------------------------------------------------------------------#

# EDIT THIS: need 100 years of simulated data.
# n_sim_years <- max(fire$year) - min(fire$year) + 1

n_sim_years  <- 100
fire_summary <- fire |>
  group_by(replicate) |>
  summarize(
    iland_firesize = mean(area_ha),
    sd_firesize    = sd(area_ha),
    iland_firefreq = n() / n_sim_years,
    .groups = "drop"
  )

if (is.na(hist_firesize) || is.na(hist_firefreq)) {
  warning("Historical fire stats are NA — skipping replicate selection; defaulting to first replicate.")
  best_rep <- rep_nums[1]
} else {
  fire_summary <- fire_summary |>
    mutate(
      firesize_diff = (iland_firesize - hist_firesize) / hist_firesize,
      firefreq_diff = (iland_firefreq - hist_firefreq) / hist_firefreq,
      total_diff    = abs(firesize_diff) + abs(firefreq_diff)
    )
  best_rep <- fire_summary$replicate[which.min(fire_summary$total_diff)]
}

cat("Replicate summary (last 100 sim years):\n")
print(as.data.frame(fire_summary))
cat("\nSelected replicate:", best_rep, "\n\n")












#------------------------------------------------------------------------------#
# Section 5: AK-wide grid FRP (landscape-independent).
# Tiles Alaska with ~60,000 ha cells (25,500 × 23,900 m — same as an iLand
# landscape) and calculates FRP, mean fire size, and fire frequency per cell
# from the historical record. Results are cached as rasters; set run_anew to
# TRUE only when the historical fire dataset changes.
# Replaces the nested sp/rgeos loop in the original with terra::intersect.
#------------------------------------------------------------------------------#
ak_grid_dir <- "/glade/work/qasena/landscape_init_ak_can/data/ak_fire_grid"
dir.create(ak_grid_dir, recursive = TRUE, showWarnings = FALSE)

cat("Computing AK grid FRP (run_anew = TRUE) — this may take several minutes...\n")

# Alaska land polygon — project to env_grid CRS (histfire already shares this CRS)
ak_poly <- terra::project(terra::vect(file.path(dsn, "AK_polygon.shp")), terra::crs(env_grid))

# Filter and fix geometry (replaces gBuffer width=0)
histfire_yr  <- histfire[!is.na(histfire$FIREYEAR) &
                         histfire$FIREYEAR >= first_year &
                         histfire$FIREYEAR <= last_year, ]
histfire_yr  <- terra::makeValid(histfire_yr)

# Dissolve by year so each resulting polygon = one fire-year per union area
# (equivalent to unionSpatialPolygons(histfire, FIREYEAR) in the original)
histfire_agg <- terra::aggregate(histfire_yr, by = "FIREYEAR", dissolve = TRUE)

# Raster template tiling AK with iLand-sized cells (env_grid CRS, metric units)
ak_grid_rast    <- terra::rast(terra::ext(histfire),
                               resolution = c(25500, 23900),
                               crs = terra::crs(env_grid))
ak_grid_rast[]  <- seq_len(terra::ncell(ak_grid_rast))

# Convert to polygons; keep only cells that overlap AK land area
ak_grid_polys         <- terra::as.polygons(ak_grid_rast)
names(ak_grid_polys)[1] <- "cell_id"
ak_grid_polys$AREA_ha <- terra::expanse(ak_grid_polys, unit = "ha")
land_mask             <- terra::relate(ak_grid_polys, ak_poly, relation = "intersects")[, 1]
ak_grid_polys         <- ak_grid_polys[land_mask, ]

# Vectorised intersect replaces per-cell gIntersection loop
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

# terra::writeRaster(terra::rasterize(ak_grid_polys, ak_grid_rast, field = "FRP"),
#                    file.path(ak_grid_dir, "frp_raster.tif"),      overwrite = TRUE)
# terra::writeRaster(terra::rasterize(ak_grid_polys, ak_grid_rast, field = "MEAN_FIRE_SIZE"),
#                    file.path(ak_grid_dir, "firesize_raster.tif"), overwrite = TRUE)
# terra::writeRaster(terra::rasterize(ak_grid_polys, ak_grid_rast, field = "FIRE_FREQ"),
#                    file.path(ak_grid_dir, "firefreq_raster.tif"), overwrite = TRUE)

cat("AK grid rasters written to:", ak_grid_dir, "\n\n")

frp_rast      <- terra::rast(file.path(ak_grid_dir, "frp_raster.tif"))
firesize_rast <- terra::rast(file.path(ak_grid_dir, "firesize_raster.tif"))
firefreq_rast <- terra::rast(file.path(ak_grid_dir, "firefreq_raster.tif"))

#------------------------------------------------------------------------------#
# Section 6: Rolling FRP for the selected replicate.
# Slides a frp_numyears window through the simulation — equivalent to the loop
# in the original Rmd (lines 492–508) but uses best_rep instead of hardcoded
# replicate==6 and landscape_area_ha instead of hardcoded cpcrw_area.
# Guard: if the historical period (frp_numyears) exceeds the simulation length,
# the window can never start — skip and warn.
#------------------------------------------------------------------------------#
fire_best <- fire[fire$replicate == best_rep, ]

# First iland year will need to be edited to filter for the last 40 years of simulation
first_ilandyear <- min(fire_best$year) + frp_numyears
last_ilandyear  <- max(fire_best$year)

if (first_ilandyear > last_ilandyear) {
  warning(
    "frp_numyears (", frp_numyears, ") exceeds simulation length (",
    n_sim_years, " years) — rolling FRP cannot be computed. Skipping."
  )
  rolling_frp_df <- data.frame(year = integer(0), iland_frp = numeric(0))
} else {
  sim_years <- first_ilandyear:last_ilandyear
  iland_frp <- vapply(sim_years, function(yr) {
    years_to_eval <- (yr - frp_numyears + 1):yr
    area_burned   <- sum(fire_best$area_ha[fire_best$year %in% years_to_eval])
    if (area_burned == 0) return(NA_real_)
    round(frp_numyears / (area_burned / landscape_area_ha), 0)
  }, numeric(1))
  rolling_frp_df <- data.frame(year = sim_years, iland_frp = iland_frp)
}

cat("Rolling FRP — replicate", best_rep, ":\n")
print(rolling_frp_df)
cat("\nFinal rolling FRP:", tail(rolling_frp_df$iland_frp, 1), "years\n\n")

write.csv(rolling_frp_df,
          file.path(output_dir, "rolling_frp.csv"),
          row.names = FALSE)

# Per-year fire summary for best replicate: annual area burned + severity.
# prop_n_died and prop_ba_died are aggregate proportions (sum killed / sum total)
# across all fire events within each year; set to 0 when denominator is 0
# (years with no trees on burning pixels — matches original Rmd handling).
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

# Scalar comparison table: observed (historical) vs simulated (best replicate).
best_stats    <- fire_summary[fire_summary$replicate == best_rep, ]
final_iland_frp <- if (nrow(rolling_frp_df) > 0) tail(rolling_frp_df$iland_frp, 1) else NA_real_

comparison_df <- data.frame(
  metric    = c("frp_years", "mean_firesize_ha", "firefreq_fires_per_year"),
  observed  = c(hist_frp,    hist_firesize,       hist_firefreq),
  simulated = c(final_iland_frp,
                best_stats$iland_firesize,
                best_stats$iland_firefreq)
)

cat("Fire comparison (observed vs simulated replicate", best_rep, "):\n")
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
