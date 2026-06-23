library(DBI)      # Rmd L20: provides dbConnect/dbReadTable/dbDisconnect interface
library(RSQLite)  # Rmd L20: SQLite backend driver for DBI
library(dplyr)    # Rmd L21: library(tidyverse) — used here for group_by/summarize/mutate
library(terra)    # replaces Rmd L22-26: raster, rgdal, rgeos, sp, maptools

#------------------------------------------------------------------------------#
# Reference script for comparing Sections 5 & 6 of process_fire_regime.R.
# Follows the original Rmd (fire-regime_script-5_09-30-2022.Rmd) as closely
# as possible with two changes only:
#   1. Paths updated to local test data.
#   2. Deprecated sp/raster/rgdal/rgeos replaced with terra equivalents.
# No CLI args; no replicate loop (test data is a single replicate).
# Outputs to workflow-output/fire_regime_comparison/ for manual CSV diff.
#------------------------------------------------------------------------------#

# Local path to a single iLand SQLite output file; replaces Rmd L158-160 on_ws path
sqlite_path   <- "Z:/personal_storage/quinn_storage/NorEsm2-MMssp126_dbh2.5_yr_31_iLand2.0/rep_3/NorEsm2-MMssp126_dbh2.5_yr_31_iLand2.0_3.sqlite"
# Local path to env.grid raster; used in place of Rmd L142 hardcoded cpcrw_area
env_grid_path <- "Z:/personal_storage/quinn_storage/landscape_init_ak_can/landscape_alaska_01/gis/env.grid.tif"
# Path to AK fire shapefile directory; replaces Rmd L197-226 on_ws dsn strings
dsn           <- "//10.60.2.10/FF_Lab/project_data/na_boreal/sensitivity_analysis/data/historic_fire/raw data/fire"
# Root output directory for comparison CSVs; no Rmd equivalent
output_dir    <- "Z:/personal_storage/quinn_storage/landscape_init_ak_can/workflow-output/fire_regime_comparison"
# Subdirectory for cached AK-wide grid rasters; mirrors Rmd L279-282 raster_loc
ak_grid_dir   <- file.path(output_dir, "ak_fire_grid")

dir.create(output_dir,  recursive = TRUE, showWarnings = FALSE)  # ensure output dir exists; no Rmd equivalent
dir.create(ak_grid_dir, recursive = TRUE, showWarnings = FALSE)  # ensure grid cache dir exists; no Rmd equivalent

# Progress header; no Rmd equivalent
cat("--- process_fire_regime_reference ---\n",
    "start time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

#------------------------------------------------------------------------------#
# Load iLand fire table (single replicate — no replicate column added)
# Equivalent to original Rmd chunk lines 156–180.
#------------------------------------------------------------------------------#
db   <- DBI::dbConnect(RSQLite::SQLite(), dbname = sqlite_path)  # Rmd L158-160: DBI::dbConnect(RSQLite::SQLite(), paste0(dbname=..., i, ...)) — single file, no loop
fire <- DBI::dbReadTable(db, "fire")                              # Rmd L161: df <- dbReadTable(db.conn, "fire")
DBI::dbDisconnect(db)                                             # Rmd L162: dbDisconnect(db.conn)

fire         <- fire[fire$area_m2 > 0, ]  # Rmd L170: fire <- fire[fire$area_m2 > 0,] — drop iLand no-burn placeholder rows
fire$area_ha <- fire$area_m2 / 10000      # Rmd L173: fire$area_ha <- fire$area_m2 / 10000 — convert m² to ha

# Load env.grid and count non-NA 100m cells; each cell = 1 ha
env_grid          <- terra::rast(env_grid_path)               # replaces Rmd L142 first factor: (25500 * 23900)
landscape_area_ha <- sum(!is.na(terra::values(env_grid)))     # replaces Rmd L142: cpcrw_area <- (25500 * 23900) / 10000

cat("landscape area (ha):", landscape_area_ha, "\n")                          # diagnostic; no Rmd equivalent
cat("Fire events loaded:", nrow(fire), "\n")                                   # diagnostic; no Rmd equivalent
cat("Year range:", paste(range(fire$year), collapse = " - "), "\n\n")         # diagnostic; no Rmd equivalent

#------------------------------------------------------------------------------#
# Section 2: Load historical AK fire perimeters and clip to landscape extent.
# Original: readOGR + raster::area → terra::vect + terra::expanse.
#------------------------------------------------------------------------------#
histfire          <- terra::vect(file.path(dsn, "AK_fire_location_polygons.shp"))  # Rmd L197-202: readOGR(dsn=..., layer="AK_fire_location_polygons")
histfire$area_ha  <- histfire$Shape_Area / 10000                                    # Rmd L203: histfire$area_ha <- histfire$Shape_Area / 10000
histfire$FIREYEAR <- as.numeric(histfire$FIREYEAR)                                  # Rmd L204: histfire$FIREYEAR <- as.numeric(histfire$FIREYEAR)
histfire          <- terra::project(histfire, terra::crs(env_grid))                # new: reproject to env_grid CRS; Rmd used spTransform only inside the grid block (L297)

cat("Historical fire polygons loaded:", nrow(histfire), "\n")                        # diagnostic; no Rmd equivalent
cat("Fire year range:", paste(range(histfire$FIREYEAR, na.rm = TRUE), collapse = " - "), "\n\n")  # diagnostic; no Rmd equivalent

# Build a single dissolved polygon of the landscape extent from non-NA env_grid cells
landscape_poly <- terra::as.polygons(         # replaces Rmd L227: readOGR(..., layer="perimeters_clipped") — derives clip polygon from env_grid instead of loading a pre-clipped shapefile
  terra::ifel(!is.na(env_grid), 1L, NA),      #   mark every non-NA env_grid cell as 1 (NA cells become NA)
  dissolve = TRUE                             #   dissolve all 1-cells into a single boundary polygon
)
terra::crs(landscape_poly) <- terra::crs(env_grid)  # assign CRS explicitly (as.polygons may drop it)

histfire_clip              <- terra::intersect(histfire, landscape_poly)     # replaces Rmd L227: pre-clipped shapefile load — clips on-the-fly
histfire_clip$clip_area_ha <- terra::expanse(histfire_clip, unit = "ha")    # Rmd L228: histfire_clip$clip_area_ha <- raster::area(histfire_clip) / 10000

cat("Fire polygons clipped to landscape:", nrow(histfire_clip), "\n\n")  # diagnostic; no Rmd equivalent

#------------------------------------------------------------------------------#
# Section 3: Observed FRP.
# Original: lines 240–265.
#------------------------------------------------------------------------------#
first_year   <- 1980                                              # Rmd L242: first_year = 1980 — pre-1980 perimeters only cover fires ≥1000 ac
last_year    <- max(histfire$FIREYEAR, na.rm = TRUE)              # Rmd L243: last_year = max(histfire$FIREYEAR)
frp_numyears <- (last_year - first_year) + 1                      # Rmd L244: frp_numyears = (last_year - first_year) + 1 — length of historical window

histfire_clip <- histfire_clip[                         # Rmd L245-247: x <- which(histfire_clip$FIREYEAR >= first_year & ... <= last_year); histfire_clip <- histfire_clip[x,]
  !is.na(histfire_clip$FIREYEAR) &                      #   added NA guard not in original
  histfire_clip$FIREYEAR >= first_year &
  histfire_clip$FIREYEAR <= last_year, ]

if (nrow(histfire_clip) == 0) {  # guard for landscapes outside historical fire record; no Rmd equivalent
  warning("No historical fire polygons in landscape for ", first_year, "-", last_year)
  hist_frp         <- NA_real_   # no Rmd equivalent — original assumed CPCRW always has fires
  hist_firesize    <- NA_real_
  sd_hist_firesize <- NA_real_
  hist_firefreq    <- NA_real_
} else {
  hist_frp         <- round(frp_numyears / (sum(histfire_clip$clip_area_ha) / landscape_area_ha), 0)  # Rmd L252: hist_frp = round(frp_numyears / (sum(histfire_clip$clip_area_ha) / cpcrw_area), 0)
  hist_firesize    <- mean(histfire_clip$clip_area_ha)                                                 # Rmd L253: hist_firesize = mean(histfire_clip$clip_area_ha)
  sd_hist_firesize <- sd(histfire_clip$clip_area_ha)                                                   # Rmd L254: sd_hist_firesize = sd(histfire_clip$clip_area_ha)
  hist_firefreq    <- nrow(histfire_clip) / frp_numyears  # Rmd L255: hist_firefreq = length(histfire_clip) / frp_numyears — length() on SPDF = n features; nrow() is equivalent
}

cat("Historical fire period:", first_year, "-", last_year, "(", frp_numyears, "years)\n")  # Rmd L257-265: cat() calls
cat("Historical FRP:        ", hist_frp, "years\n")
cat("Mean historical size:  ", round(hist_firesize, 0), "ha\n")
cat("Historical fire freq:  ", round(hist_firefreq, 2), "fires/year\n\n")

#------------------------------------------------------------------------------#
# Section 4: No replicate selection — single replicate in test data.
# Compute fire_summary for the comparison table output.
#------------------------------------------------------------------------------#
# n_sim_years  <- max(fire$year) - min(fire$year) + 1  # alternative: derive from data
n_sim_years  <- 100  # Rmd L482 context: iland_firefreq = length(area_ha)/100 — 100 sim years hardcoded
fire_summary <- data.frame(                          # Rmd L482-485: iland.fire.summary = fire %>% filter(year>200) %>% group_by(replicate) %>% summarize(...)
  iland_firesize = mean(fire$area_ha),               #   Rmd L483: iland_firesize = mean(area_ha)
  sd_firesize    = sd(fire$area_ha),                 #   Rmd L484: sd_fire_size = sd(area_ha)
  iland_firefreq = nrow(fire) / n_sim_years          #   Rmd L485: iland_firefreq = length(area_ha)/100
)
fire_best <- fire  # Rmd L492: fire.analyze=fire %>%filter(replicate==6) — no replicate filter needed for single rep

cat("Simulation years:", n_sim_years, "\n")                                          # diagnostic; no Rmd equivalent
cat("Mean iLand fire size:  ", round(fire_summary$iland_firesize, 0), "ha\n")
cat("iLand fire frequency:  ", round(fire_summary$iland_firefreq, 2), "fires/year\n\n")













#------------------------------------------------------------------------------#
# Section 5: AK-wide grid FRP.
# Original: per-cell gIntersection loop with sp/rgeos — replaced with
# terra::intersect (vectorised). Grid built with terra::rast + as.polygons
# instead of manual SpatialPolygons loop. All other logic unchanged.
# Original Rmd lines 276–424.
#------------------------------------------------------------------------------#
# Run if cached raster absent; Rmd L277: run_anew = F (default off; reference always recomputes when cache missing)
run_anew <- !file.exists(file.path(ak_grid_dir, "frp_raster.tif"))

if (run_anew) {
  cat("Computing AK grid FRP (run_anew = TRUE)...\n")

  # Load and reproject AK outline polygon; Rmd L293-297: ak <- readOGR(dsn, layer="AK_polygon"); ak <- spTransform(ak, proj4string(histfire))
  ak_poly <- terra::project(
    terra::vect(file.path(dsn, "AK_polygon.shp")),
    terra::crs(env_grid)
  )

  # Subset histfire to the analysis window; Rmd L287-289: x <- which(histfire$FIREYEAR >= first_year & ... <= last_year); histfire <- histfire[x,]
  histfire_yr  <- histfire[!is.na(histfire$FIREYEAR) &
                            histfire$FIREYEAR >= first_year &
                            histfire$FIREYEAR <= last_year, ]
  # Fix self-intersections; Rmd L361: histfire <- gBuffer(histfire, byid=T, width=0) — zero-width buffer replaced by makeValid
  histfire_yr  <- terra::makeValid(histfire_yr)
  # Dissolve perimeters by year so each output polygon = one fire-year union area; Rmd L367: histfire_oneyear <- unionSpatialPolygons(histfire, histfire@data$FIREYEAR)
  histfire_agg <- terra::aggregate(histfire_yr, by = "FIREYEAR", dissolve = TRUE)

  # Build raster template tiling AK at iLand landscape cell size; Rmd L300-311: x_left/x_right/y_bottom/y_top seq() grid — terra::rast replaces manual bbox + seq() construction
  ak_grid_rast       <- terra::rast(terra::ext(histfire),
                                   resolution = c(25500, 23900),  # Rmd L300-301: xlength = 25500; ylength = 23900
                                   crs = terra::crs(env_grid))
  ak_grid_rast[]     <- seq_len(terra::ncell(ak_grid_rast))  # assign unique integer cell IDs; Rmd L341: data.frame(ID = 1:length(poly_list))

  # Convert raster cells to polygons; Rmd L336-341: SpatialPolygons(poly_list); SpatialPolygonsDataFrame(...) — loop replaced by as.polygons
  ak_grid_polys      <- terra::as.polygons(ak_grid_rast)
  names(ak_grid_polys)[1] <- "cell_id"                              # rename ID field for join clarity
  ak_grid_polys$AREA_ha   <- terra::expanse(ak_grid_polys, unit = "ha")  # Rmd L352: ak_grid$AREA <- raster::area(ak_grid)/10000

  # Keep only cells that overlap AK land; Rmd L347-349: int <- over(ak_grid, ak, returnList=T); land_area <- sapply(int, ...); ak_grid <- ak_grid[land_area,]
  land_mask     <- terra::relate(ak_grid_polys, ak_poly, relation = "intersects")[, 1]
  ak_grid_polys <- ak_grid_polys[land_mask, ]

  # Vectorised intersect of grid cells × fire-year polygons; Rmd L371-386: for(i in 1:nrow(ak_grid)) { hist_clip <- gIntersection(one_grid, histfire_oneyear, byid=T); ... } — single call replaces per-cell loop
  fire_x_grid              <- terra::intersect(ak_grid_polys, histfire_agg)
  fire_x_grid$clip_area_ha <- terra::expanse(fire_x_grid, unit = "ha")  # Rmd L377: hist_clip$clip_area_ha <- raster::area(hist_clip) / 10000

  # Summarise burned area, fire count, and mean size per grid cell; Rmd L378-384: ak_grid$FRP, ak_grid$NUM_FIRES, ak_grid$MEAN_FIRE_SIZE filled inside loop
  cell_stats <- as.data.frame(fire_x_grid)[, c("cell_id", "clip_area_ha")] |>
    group_by(cell_id) |>
    summarize(
      total_burned_ha = sum(clip_area_ha),   # Rmd L378-379: sum(hist_clip$clip_area_ha) for FRP denominator
      num_fires       = n(),                 # Rmd L384: ak_grid$NUM_FIRES[i] <- length(hist_clip)
      mean_firesize   = mean(clip_area_ha),  # Rmd L382: ak_grid$MEAN_FIRE_SIZE[i] <- mean(hist_clip$clip_area_ha)
      .groups = "drop"
    )

  # Join cell stats back to grid polygons and compute FRP/FIRE_FREQ; Rmd L378-395
  grid_df <- dplyr::left_join(as.data.frame(ak_grid_polys), cell_stats, by = "cell_id") |>
    mutate(
      FRP            = round(frp_numyears / (total_burned_ha / AREA_ha), 0),  # Rmd L378-379: ak_grid$FRP[i] <- round(frp_numyears / (sum(...) / ak_grid$AREA[i]), 0)
      FRP            = ifelse(!is.na(FRP) & FRP > 10000, NA, FRP),            # Rmd L391: ak_grid$FRP[ak_grid$FRP > 10000] <- NA — cap implausible values
      FIRE_FREQ      = ifelse(is.na(num_fires) | num_fires == 0, NA,
                              frp_numyears / num_fires),                     # Rmd L394-395: ak_grid$FIRE_FREQ <- ifelse(ak_grid$NUM_FIRES == 0, NA, frp_numyears / ak_grid$NUM_FIRES)
      MEAN_FIRE_SIZE = mean_firesize                                           # Rmd L382: ak_grid$MEAN_FIRE_SIZE
    )

  ak_grid_polys$FRP            <- grid_df$FRP             # Rmd L354: ak_grid$FRP = NA (initialised); values written in loop; here assigned after vectorised summarise
  ak_grid_polys$MEAN_FIRE_SIZE <- grid_df$MEAN_FIRE_SIZE  # Rmd L355: ak_grid$MEAN_FIRE_SIZE = 0 (initialised)
  ak_grid_polys$FIRE_FREQ      <- grid_df$FIRE_FREQ       # Rmd L394-395: computed and assigned to ak_grid$FIRE_FREQ

  # Write rasters for later re-use; Rmd L401-402: writeRaster(frpras, paste0(raster_loc, "/frp_raster.tif"), ...)
  terra::writeRaster(terra::rasterize(ak_grid_polys, ak_grid_rast, field = "FRP"),
                     file.path(ak_grid_dir, "frp_raster.tif"),      overwrite = TRUE)
  # Rmd L404-408: writeRaster(firesizeras, ...)
  terra::writeRaster(terra::rasterize(ak_grid_polys, ak_grid_rast, field = "MEAN_FIRE_SIZE"),
                     file.path(ak_grid_dir, "firesize_raster.tif"), overwrite = TRUE)
  # Rmd L410-415: writeRaster(firefreqras, ...)
  terra::writeRaster(terra::rasterize(ak_grid_polys, ak_grid_rast, field = "FIRE_FREQ"),
                     file.path(ak_grid_dir, "firefreq_raster.tif"), overwrite = TRUE)

  cat("AK grid rasters written to:", ak_grid_dir, "\n\n")
} else {
  cat("AK grid rasters already exist — loading from cache.\n\n")
}

frp_rast      <- terra::rast(file.path(ak_grid_dir, "frp_raster.tif"))      # Rmd L419: frpras <- raster(paste0(raster_loc, "/frp_raster.tif"))
firesize_rast <- terra::rast(file.path(ak_grid_dir, "firesize_raster.tif")) # Rmd L421: firesizeras <- raster(...)
firefreq_rast <- terra::rast(file.path(ak_grid_dir, "firefreq_raster.tif")) # Rmd L423: firefreqras <- raster(...)

#------------------------------------------------------------------------------#
# Section 6: Rolling FRP — original Rmd for loop (lines 494–508).
# Only substitutions: replicate==6 → no filter (single rep);
# cpcrw_area → landscape_area_ha. Loop structure unchanged.
#------------------------------------------------------------------------------#
# First valid year for a full frp_numyears window; Rmd L493: first_ilandyear = min(fire.analyze$year)+frp_numyears
first_ilandyear <- min(fire_best$year) + frp_numyears
last_ilandyear  <- max(fire_best$year)  # Rmd L494: max(fire.analyze$year) used as loop upper bound

if (first_ilandyear > last_ilandyear) {  # guard: window longer than simulation; no Rmd equivalent
  warning("frp_numyears (", frp_numyears, ") exceeds simulation length (",
          n_sim_years, " years) — rolling FRP cannot be computed. Skipping.")
  rolling_frp_df <- data.frame(year = integer(0), iland_frp = numeric(0))
} else {
  iland_frp <- rep(NA_real_, last_ilandyear - first_ilandyear + 1)  # Rmd L494: iland_frp = rep(NA, (max(fire.analyze$year) - first_ilandyear+1))
  count     <- 1                                                      # Rmd L495: count = 1
  for (yr in first_ilandyear:last_ilandyear) {                        # Rmd L496: for (yr in (first_ilandyear:max(fire.analyze$year)))
    years_to_eval    <- (yr - frp_numyears + 1):yr                   # Rmd L499: years_to_eval <- (yr - (frp_numyears) + 1):yr — sliding window of frp_numyears length
    area_burned      <- sum(fire_best$area_ha[fire_best$year %in% years_to_eval])  # Rmd L502: area_burned <- sum(fire.analyze$area_ha[fire.analyze$year %in% years_to_eval])
    iland_frp[count] <- round(frp_numyears / (area_burned / landscape_area_ha), 0) # Rmd L505: iland_frp[count] <- round(frp_numyears / (area_burned / cpcrw_area), 0)
    count            <- count + 1                                     # Rmd L507: count = count + 1
  }
  rolling_frp_df <- data.frame(year = first_ilandyear:last_ilandyear, iland_frp)  # Rmd L519-520: data.frame(year=first_ilandyear:max(...), frp=iland_frp) used for ggplot
}

cat("Rolling FRP (single replicate):\n")
print(rolling_frp_df)
cat("\nFinal rolling FRP:", tail(rolling_frp_df$iland_frp, 1), "years\n\n")  # Rmd L562: tail(iland_frp,n=1) used as geom_vline xintercept

# Write rolling FRP series; no Rmd equivalent (original plotted directly)
write.csv(rolling_frp_df,
          file.path(output_dir, "rolling_frp.csv"),
          row.names = FALSE)

# Per-year fire summary; Rmd L649-651: summ_fire_iland <- fire %>% filter(replicate==6) %>% group_by(year) %>% summarise(total_area=sum(area_ha), prop_n_died=n_trees_died/n_trees, prop_ba_died=basalArea_died/basalArea_total)
# prop_n_died / prop_ba_died computed as aggregate proportions (sum killed / sum total) rather than per-row ratios to avoid NaN when a row has n_trees==0
annual_fire <- fire_best |>
  group_by(year) |>
  summarize(
    total_area_ha = sum(area_ha),   # Rmd L650: total_area = sum(area_ha)
    prop_n_died   = {               # Rmd L650: prop_n_died = n_trees_died/n_trees — reformulated as aggregate fraction
      d <- sum(n_trees, na.rm = TRUE)
      if (d == 0) 0 else sum(n_trees_died, na.rm = TRUE) / d  # Rmd L652-653: NA → 0 replacement applied after; here guarded pre-division
    },
    prop_ba_died  = {               # Rmd L651: prop_ba_died = basalArea_died / basalArea_total — same aggregate approach
      d <- sum(basalArea_total, na.rm = TRUE)
      if (d == 0) 0 else sum(basalArea_died, na.rm = TRUE) / d
    },
    .groups = "drop"
  )

# Write annual fire summary; no Rmd equivalent (original produced ggplot figures)
write.csv(annual_fire,
          file.path(output_dir, "annual_fire_summary.csv"),
          row.names = FALSE)

# Final rolling FRP scalar (last window value); Rmd L562: tail(iland_frp,n=1)
final_iland_frp <- if (nrow(rolling_frp_df) > 0) tail(rolling_frp_df$iland_frp, 1) else NA_real_

# Scalar comparison table: observed (historical) vs simulated; no direct Rmd equivalent (original produced density plots)
comparison_df <- data.frame(
  metric    = c("frp_years", "mean_firesize_ha", "firefreq_fires_per_year"),
  observed  = c(hist_frp,    hist_firesize,       hist_firefreq),   # Rmd L252-255: hist_frp, hist_firesize, hist_firefreq
  simulated = c(final_iland_frp,
                fire_summary$iland_firesize,                         # Rmd L483: iland_firesize = mean(area_ha)
                fire_summary$iland_firefreq)                         # Rmd L485: iland_firefreq = length(area_ha)/100
)

cat("Fire comparison (observed vs simulated):\n")
print(comparison_df)
cat("\n")

# Write comparison table; no Rmd equivalent
write.csv(comparison_df,
          file.path(output_dir, "fire_comparison.csv"),
          row.names = FALSE)

cat("Outputs written to:", output_dir, "\n")
cat("  rolling_frp.csv\n")
cat("  annual_fire_summary.csv\n")
cat("  fire_comparison.csv\n")
cat("\nDone:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
