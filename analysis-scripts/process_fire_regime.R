library(DBI)
library(RSQLite)
library(dplyr)

# CLI arguments: landscape and treatment are passed by the calling script/bash job; no Rmd equivalent
args      <- commandArgs(TRUE)
landscape <- args[1]   # e.g. "landscape_alaska_01_1950-1980spinup"
treatment <- args[2]   # e.g. "NorEsm2-MMssp126_dbh2.5_onlysimfalse_yr_1_iLand2.1"

# HPC paths constructed from args; replaces Rmd L155-163 on_ws flag + hardcoded workspace paths
user       <- "qasena"
data_path  <- paste0("/glade/derecho/scratch/", user, "/output_ak_can/", landscape, "/")
output_dir <- file.path(data_path, "processed", treatment, "fire_regime")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)  # ensure output dir exists; no Rmd equivalent

# Progress header; no Rmd equivalent
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
# Strip spinup suffix from landscape name to find the corresponding init directory; no Rmd equivalent
landscape_dir     <- sub("^(landscape_[^_]+_\\d+)_.*", "\\1", landscape)
env_path          <- paste0("/glade/work/qasena/landscape_init_ak_can/", landscape_dir, "/gis/env.grid.tif")
env_grid          <- terra::rast(env_path)                        # replaces Rmd L142 first factor: (25500 * 23900)
landscape_area_ha <- sum(!is.na(terra::values(env_grid)))         # replaces Rmd L142: cpcrw_area <- (25500 * 23900) / 10000

cat("landscape area (ha):", landscape_area_ha, "\n\n")  # diagnostic; no Rmd equivalent

#------------------------------------------------------------------------------#
# Section 1: Load iLand fire data.
# Discover replicate directories and load fire table from each SQLite file.
# Replicates are inferred from directory names (rep_1, rep_2, ...) so the
# script works for any number of replicates without hardcoding.
#------------------------------------------------------------------------------#
# List rep_N subdirectories and extract integer replicate numbers; Rmd L157: for(i in 1:10) — hardcoded 10 replicates
rep_dirs <- list.dirs(file.path(data_path, treatment), recursive = FALSE, full.names = FALSE)
rep_nums  <- sort(as.integer(sub("rep_", "", grep("^rep_", rep_dirs, value = TRUE))))

if (length(rep_nums) == 0) stop("No replicate directories found in: ", file.path(data_path, treatment))  # guard; no Rmd equivalent

cat("Found replicates:", paste(rep_nums, collapse = ", "), "\n\n")  # diagnostic; no Rmd equivalent

# Load fire table from each replicate SQLite and bind into one data frame; Rmd L157-168: for loop over i=1:10 reading CPCRW_sm_i.sqlite, rbind(fire,df)
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
  db <- DBI::dbConnect(RSQLite::SQLite(), dbname = input_file)  # Rmd L159: db.conn <- DBI::dbConnect(RSQLite::SQLite(), ...)
  df <- DBI::dbReadTable(db, "fire")                            # Rmd L161: df <- dbReadTable(db.conn, "fire")
  DBI::dbDisconnect(db)                                         # Rmd L162: dbDisconnect(db.conn)
  df$replicate <- rep                                           # Rmd L166: df$replicate=i
  # Filter could end up with empty data frame if no fire in last 100 years of sim (unlikely)
  df <- df |> filter(year >= 200)                               # Rmd L482: fire %>% filter(year>200) — keep only post-spinup years
  df
}))



#------------------------------------------------------------------------------#
      # Temporary files for testing
      fire <- DBI::dbConnect(RSQLite::SQLite(),
          dbname = "Z:/personal_storage/quinn_storage/NorEsm2-MMssp126_dbh2.5_yr_31_iLand2.0/rep_3/NorEsm2-MMssp126_dbh2.5_yr_31_iLand2.0_3.sqlite") |>
        DBI::dbReadTable("fire") |>
        filter(year >= 200) |>
        mutate(replicate = 3)
      env_grid <-terra::rast("Z:/personal_storage/quinn_storage/landscape_init_ak_can/landscape_alaska_01/gis/env.grid.tif")
      landscape_area_ha <- sum(!is.na(terra::values(env_grid)))

      dsn <- "Z:/personal_storage/quinn_storage/landscape_init_ak_can/data/historic_fire/raw_data/fire"
      histfire <- terra::vect(file.path(dsn, "AK_fire_location_polygons.shp"))
#------------------------------------------------------------------------------#



# Drop events where nothing burned (area_m2 == 0 rows are iLand no-fire records)
fire <- fire[fire$area_m2 > 0, ]   # Rmd L170: fire <- fire[fire$area_m2 > 0,]
fire$area_ha <- fire$area_m2 / 10000  # Rmd L173: fire$area_ha <- fire$area_m2 / 10000 — convert m² to ha

cat("Fire events loaded:", nrow(fire), "\n")
cat("Year range:        ", paste(range(fire$year), collapse = " – "), "\n")
cat("Replicates in data:", paste(sort(unique(fire$replicate)), collapse = ", "), "\n\n")

#------------------------------------------------------------------------------#
# Section 2: Load historical AK fire perimeters and clip to landscape extent.
# Replaces readOGR + raster::area() from original; uses terra::vect + expanse.
# DSN is a network drive path — update to HPC path before running on Derecho.
#------------------------------------------------------------------------------#
# HPC path to AK fire shapefile; Rmd L197-226: readOGR(dsn=...) with on_ws flag
dsn <- "/glade/work/qasena/landscape_init_ak_can/data/historic_fire/raw_data/fire"
histfire <- terra::vect(file.path(dsn, "AK_fire_location_polygons.shp"))  # Rmd L197-202: readOGR(dsn=..., layer="AK_fire_location_polygons")

histfire$area_ha  <- histfire$Shape_Area / 10000   # Rmd L203: histfire$area_ha <- histfire$Shape_Area / 10000
histfire$FIREYEAR <- as.numeric(histfire$FIREYEAR) # Rmd L204: histfire$FIREYEAR <- as.numeric(histfire$FIREYEAR)

# Reproject to env_grid CRS so all subsequent spatial operations share one CRS.
histfire <- terra::project(histfire, terra::crs(env_grid))  # new: reproject to env_grid CRS; Rmd used spTransform only inside the grid block (L297)

cat("Historical fire polygons loaded:", nrow(histfire), "\n")
cat("Fire year range:", paste(range(histfire$FIREYEAR, na.rm = TRUE), collapse = " – "), "\n\n")

# Clip historical perimeters to the landscape spatial extent.
# histfire is already in env_grid CRS so no intermediate reprojection is needed.

# Build a single dissolved polygon of the landscape extent from non-NA env_grid cells
landscape_poly <- terra::as.polygons(         # replaces Rmd L227: readOGR(..., layer="perimeters_clipped") — derives clip polygon from env_grid instead of loading a pre-clipped shapefile
  terra::ifel(!is.na(env_grid), 1L, NA),      #   mark every non-NA env_grid cell as 1 (NA cells become NA)
  dissolve = TRUE                             #   dissolve all 1-cells into a single boundary polygon
)
terra::crs(landscape_poly) <- terra::crs(env_grid)  # assign CRS explicitly (as.polygons may drop it)

histfire_clip              <- terra::intersect(histfire, landscape_poly)    # replaces Rmd L227: pre-clipped shapefile load — clips on-the-fly
histfire_clip$clip_area_ha <- terra::expanse(histfire_clip, unit = "ha")   # Rmd L228: histfire_clip$clip_area_ha <- raster::area(histfire_clip) / 10000

cat("Fire polygons clipped to landscape:", nrow(histfire_clip), "\n\n")  # diagnostic; no Rmd equivalent

#------------------------------------------------------------------------------#
# Section 3: Observed FRP for the landscape area.
# FRP = time (years) / (total burned area / area of interest).
# Period: 1980–present; pre-1980 data are less complete (perimeters >1000 ac only).
# frp_numyears and first_year are kept as named scalars — reused in Sections 5 & 6.
#------------------------------------------------------------------------------#
first_year   <- 1980                                          # Rmd L242: first_year = 1980 — pre-1980 perimeters only cover fires ≥1000 ac
last_year    <- max(histfire$FIREYEAR, na.rm = TRUE)          # Rmd L243: last_year = max(histfire$FIREYEAR)
frp_numyears <- (last_year - first_year) + 1                  # Rmd L244: frp_numyears = (last_year - first_year) + 1 — length of historical window

histfire_clip <- histfire_clip[                    # Rmd L245-247: x <- which(histfire_clip$FIREYEAR >= first_year & ... <= last_year); histfire_clip <- histfire_clip[x,]
  !is.na(histfire_clip$FIREYEAR) &                 #   added NA guard not present in original
  histfire_clip$FIREYEAR >= first_year &
  histfire_clip$FIREYEAR <= last_year, ]

if (nrow(histfire_clip) == 0) {  # guard for landscapes outside historical fire record; no Rmd equivalent
  warning("No historical fire polygons within landscape extent for ", first_year, "–", last_year,
          ". hist_frp will be NA.")
  hist_frp      <- NA_real_   # no Rmd equivalent — original assumed CPCRW always has fires
  hist_firesize <- NA_real_
  sd_hist_firesize <- NA_real_
  hist_firefreq <- NA_real_
} else {
  hist_frp      <- round(frp_numyears / (sum(histfire_clip$clip_area_ha) / landscape_area_ha), 0)  # Rmd L252: hist_frp = round(frp_numyears / (sum(histfire_clip$clip_area_ha) / cpcrw_area), 0)
  hist_firesize <- mean(histfire_clip$clip_area_ha)                                                 # Rmd L253: hist_firesize = mean(histfire_clip$clip_area_ha)
  sd_hist_firesize <- sd(histfire_clip$clip_area_ha)                                                # Rmd L254: sd_hist_firesize = sd(histfire_clip$clip_area_ha)
  hist_firefreq <- nrow(histfire_clip) / frp_numyears  # Rmd L255: hist_firefreq = length(histfire_clip) / frp_numyears — length() on SPDF = n features; nrow() is equivalent
}

cat("Historical fire period:     ", first_year, "–", last_year, "(", frp_numyears, "years)\n")  # Rmd L257-265: cat() calls
cat("Historical FRP (landscape): ", hist_frp, "years\n")
cat("Mean historical fire size:  ", round(hist_firesize, 0), "ha\n")
cat("Historical fire frequency:  ", round(hist_firefreq, 2), "fires/year\n\n")

#------------------------------------------------------------------------------#
# Section 4: Replicate selection.
# Summarise iLand fire stats over the last 100 simulation years per replicate,
# compare to observed (hist_firesize, hist_firefreq) via relative difference,
# and select the replicate with the smallest combined absolute difference.
#------------------------------------------------------------------------------#

# Rmd L482 context: iland_firefreq = length(area_ha)/100 — 100 sim years hardcoded
n_sim_years  <- 100
# Summarise fire stats per replicate; Rmd L482-485: iland.fire.summary = fire %>% filter(year>200) %>% group_by(replicate) %>% summarize(iland_firesize=..., sd_fire_size=..., iland_firefreq=...)
fire_summary <- fire |>
  group_by(replicate) |>
  summarize(
    iland_firesize = mean(area_ha),            # Rmd L483: iland_firesize = mean(area_ha)
    sd_firesize    = sd(area_ha),              # Rmd L484: sd_fire_size = sd(area_ha)
    iland_firefreq = n() / n_sim_years,        # Rmd L485: iland_firefreq = length(area_ha)/100
    .groups = "drop"
  )

if (is.na(hist_firesize) || is.na(hist_firefreq)) {  # guard for no historical data; no Rmd equivalent
  warning("Historical fire stats are NA — skipping replicate selection; defaulting to first replicate.")
  best_rep <- rep_nums[1]
} else {
  # Compute relative differences and select replicate with smallest total; Rmd L486-489: iland.fire.summary %>% mutate(fire.size.diff=..., fire.num.diff=..., total.diff=...)
  fire_summary <- fire_summary |>
    mutate(
      firesize_diff = (iland_firesize - hist_firesize) / hist_firesize,  # Rmd L487: fire.size.diff = (iland_firesize-3823)/3823 — hardcoded CPCRW value replaced by hist_firesize
      firefreq_diff = (iland_firefreq - hist_firefreq) / hist_firefreq,  # Rmd L488: fire.num.diff = (iland_firefreq - 0.12)/0.12 — hardcoded CPCRW value replaced by hist_firefreq
      total_diff    = abs(firesize_diff) + abs(firefreq_diff)             # Rmd L489: total.diff = abs(fire.size.diff) + abs(fire.num.diff)
    )
  best_rep <- fire_summary$replicate[which.min(fire_summary$total_diff)]  # Rmd L492: fire.analyze=fire %>%filter(replicate==6) — 6 was chosen manually; here selected programmatically
}

cat("Replicate summary (last 100 sim years):\n")
print(as.data.frame(fire_summary))
cat("\nSelected replicate:", best_rep, "\n\n")  # diagnostic; no Rmd equivalent












#------------------------------------------------------------------------------#
# Section 5: AK-wide grid fire statistics (landscape-independent).
#
# PURPOSE: Build a boreal-wide reference distribution of fire behaviour so that
# each iLand landscape's simulated fire regime (Section 6) can be placed in
# ecological context. The grid cells are the same size as an iLand landscape
# (~60,000 ha, 25,500 × 23,900 m), so the per-cell statistics are directly
# comparable to the per-landscape statistics computed in Sections 3 & 6.
#
# Steps:
#   1. Tile Alaska at iLand landscape resolution.
#   2. Clip to boreal domain (ecologically relevant zone).
#   3. Intersect each grid cell with the historical fire record.
#   4. Compute FRP, mean fire size, and fire frequency per cell.
#
# Output: ak_grid_polys with columns FRP, MEAN_FIRE_SIZE, FIRE_FREQ — written
# to ak_grid_stats.csv at the end of Section 6.
# Replaces the nested sp/rgeos per-cell loop in the original with terra::intersect.
#------------------------------------------------------------------------------#

# AK outline polygon — used to discard grid cells that fall entirely in the ocean
ak_poly <- terra::project(terra::vect(file.path(dsn, "AK_polygon.shp")), terra::crs(env_grid))  # Rmd L293-297: readOGR + spTransform

# Filter fire record to the analysis window and repair any invalid geometries
# (self-intersections etc. can cause gIntersection to fail in the original)
histfire_yr <- histfire[!is.na(histfire$FIREYEAR) &
                        histfire$FIREYEAR >= first_year &
                        histfire$FIREYEAR <= last_year, ]
histfire_yr <- terra::makeValid(histfire_yr)  # Rmd L361: gBuffer(width=0) — makeValid is the terra equivalent

# Dissolve individual fire polygons into one polygon per year so that overlapping
# perimeters from the same year are not double-counted in the burned-area totals
histfire_agg <- terra::aggregate(histfire_yr, by = "FIREYEAR", dissolve = TRUE)  # Rmd L367: unionSpatialPolygons

# Build a regular grid at iLand landscape resolution covering the extent of the
# fire record, then assign each cell a unique integer ID
ak_grid_rast    <- terra::rast(terra::ext(histfire),
                               resolution = c(25500, 23900),  # Rmd L300-301: xlength/ylength
                               crs = terra::crs(env_grid))
ak_grid_rast[]  <- seq_len(terra::ncell(ak_grid_rast))

# Convert the raster grid to polygons for spatial intersection
ak_grid_polys         <- terra::as.polygons(ak_grid_rast)  # Rmd L336-341: SpatialPolygons loop
names(ak_grid_polys)[1] <- "cell_id"
ak_grid_polys$AREA_ha <- terra::expanse(ak_grid_polys, unit = "ha")  # Rmd L352: raster::area / 10000

# Discard cells that do not overlap AK land (open ocean, outside study area)
land_mask     <- terra::relate(ak_grid_polys, ak_poly, relation = "intersects")[, 1]  # Rmd L347-349: over() + sapply
ak_grid_polys <- ak_grid_polys[land_mask, ]

# Clip to the boreal domain so the reference distribution reflects the same
# ecological zone as the iLand landscapes; Rmd L442: mask(frpras, spTransform(boreal, ...))
boreal_poly   <- terra::project(terra::vect(file.path(dsn, "boreal_domain.shp")), terra::crs(env_grid))
boreal_mask   <- terra::relate(ak_grid_polys, boreal_poly, relation = "intersects")[, 1]
ak_grid_polys <- ak_grid_polys[boreal_mask, ]

# Intersect every boreal grid cell with the year-dissolved fire record in one
# vectorised call; each row of fire_x_grid is one (cell × fire-year) combination
fire_x_grid              <- terra::intersect(ak_grid_polys, histfire_agg)  # Rmd L371-386: per-cell gIntersection loop
fire_x_grid$clip_area_ha <- terra::expanse(fire_x_grid, unit = "ha")       # Rmd L377: raster::area / 10000

# Aggregate intersection results to one row per grid cell: total burned area
# across all years, fire count, and mean fire size
cell_stats <- as.data.frame(fire_x_grid)[, c("cell_id", "clip_area_ha")] |>
  group_by(cell_id) |>
  summarize(
    total_burned_ha = sum(clip_area_ha),  # summed across all years — used as FRP denominator
    num_fires       = n(),                # count of fire-year intersections per cell
    mean_firesize   = mean(clip_area_ha), # mean clipped area per fire-year event
    .groups = "drop"
  )

# Join per-cell statistics back to the grid polygons and derive the three
# summary metrics that will form the reference distribution
grid_df <- dplyr::left_join(as.data.frame(ak_grid_polys), cell_stats, by = "cell_id") |>
  mutate(
    FRP = round(frp_numyears / (total_burned_ha / AREA_ha), 0),   # fire rotation period (years)
    FRP = ifelse(!is.na(FRP) & FRP > 10000, NA, FRP),             # Rmd L391: cap implausible values
    FIRE_FREQ = ifelse(is.na(num_fires) | num_fires == 0, NA,
                       frp_numyears / num_fires),                  # mean years between fire events
    MEAN_FIRE_SIZE = mean_firesize
  )

ak_grid_polys$FRP            <- grid_df$FRP
ak_grid_polys$MEAN_FIRE_SIZE <- grid_df$MEAN_FIRE_SIZE
ak_grid_polys$FIRE_FREQ      <- grid_df$FIRE_FREQ

#------------------------------------------------------------------------------#
# Section 6: Rolling FRP for the selected replicate.
# Slides a frp_numyears window through the simulation — equivalent to the loop
# in the original Rmd (lines 492–508) but uses best_rep instead of hardcoded
# replicate==6 and landscape_area_ha instead of hardcoded cpcrw_area.
# Guard: if the historical period (frp_numyears) exceeds the simulation length,
# the window can never start — skip and warn.
#------------------------------------------------------------------------------#
# Filter combined fire table to the selected replicate; Rmd L492: fire.analyze=fire %>%filter(replicate==6) — replicate chosen programmatically above
fire_best <- fire[fire$replicate == best_rep, ]

# First valid year for a full frp_numyears window; Rmd L493: first_ilandyear = min(fire.analyze$year)+frp_numyears
first_ilandyear <- min(fire_best$year) + frp_numyears
last_ilandyear  <- max(fire_best$year)  # Rmd L494: max(fire.analyze$year) used as loop upper bound

if (first_ilandyear > last_ilandyear) {  # guard: window longer than simulation; no Rmd equivalent
  warning(
    "frp_numyears (", frp_numyears, ") exceeds simulation length (",
    n_sim_years, " years) — rolling FRP cannot be computed. Skipping."
  )
  rolling_frp_df <- data.frame(year = integer(0), iland_frp = numeric(0))
} else {
  sim_years <- first_ilandyear:last_ilandyear
  # vapply replaces the for+count loop; Rmd L495-508: iland_frp=rep(NA,...); count=1; for(yr in ...) { ... count=count+1 }
  iland_frp <- vapply(sim_years, function(yr) {
    years_to_eval <- (yr - frp_numyears + 1):yr              # Rmd L499: years_to_eval <- (yr - (frp_numyears) + 1):yr — sliding window of frp_numyears length
    area_burned   <- sum(fire_best$area_ha[fire_best$year %in% years_to_eval])  # Rmd L502: area_burned <- sum(fire.analyze$area_ha[...])
    if (area_burned == 0) return(NA_real_)                   # added guard: avoid Inf FRP; no Rmd equivalent
    round(frp_numyears / (area_burned / landscape_area_ha), 0)  # Rmd L505: iland_frp[count] <- round(frp_numyears / (area_burned / cpcrw_area), 0)
  }, numeric(1))
  rolling_frp_df <- data.frame(year = sim_years, iland_frp = iland_frp)  # Rmd L519-520: data.frame(year=first_ilandyear:max(...), frp=iland_frp) used for ggplot
}


# Write rolling FRP series; no Rmd equivalent (original plotted directly)
write.csv(rolling_frp_df,
          file.path(output_dir, "rolling_frp.csv"),
          row.names = FALSE)


# Scalar comparison table: observed (historical) vs simulated (best replicate); no direct Rmd equivalent (original produced density plots)
best_stats    <- fire_summary[fire_summary$replicate == best_rep, ]  # pull best-rep row from fire_summary
final_iland_frp <- if (nrow(rolling_frp_df) > 0) tail(rolling_frp_df$iland_frp, 1) else NA_real_  # Rmd L562: tail(iland_frp,n=1)


comparison_df <- data.frame(
  metric    = c("frp_years", "mean_firesize_ha", "firefreq_fires_per_year"),
  observed  = c(hist_frp,    hist_firesize,       hist_firefreq),   # Rmd L252-255: hist_frp, hist_firesize, hist_firefreq
  simulated = c(final_iland_frp,
                best_stats$iland_firesize,                           # Rmd L483: iland_firesize = mean(area_ha)
                best_stats$iland_firefreq)                           # Rmd L485: iland_firefreq = length(area_ha)/100
)


# Write comparison table; no Rmd equivalent
write.csv(comparison_df,
          file.path(output_dir, "fire_comparison.csv"),
          row.names = FALSE)

# Write per-replicate iLand fire summary; Rmd L482-489: iland.fire.summary — used to select best_rep and as vertical lines in density plots
write.csv(fire_summary,
          file.path(output_dir, "annual_fire_summary.csv"),
          row.names = FALSE)

# Extract the boreal-wide reference distribution from ak_grid_polys (already boreal-
# clipped in Section 5). This is the equivalent of dat.orig in the original Rmd
# (lines 543-546) and provides the background for the fire-size and fire-frequency
# density plots. FIRE_FREQ (years between fires) is converted to annual probability
# (fires per year) to match the iLand firefreq metric and the original's 1/firefreqras.
ak_grid_stats <- as.data.frame(ak_grid_polys)[, c("cell_id", "FRP", "MEAN_FIRE_SIZE", "FIRE_FREQ")] |>
  dplyr::rename(frp = FRP, firesize = MEAN_FIRE_SIZE) |>
  dplyr::mutate(
    firefreq = ifelse(!is.na(FIRE_FREQ) & FIRE_FREQ > 0, 1 / FIRE_FREQ, NA)
  ) |>
  dplyr::select(-FIRE_FREQ)

write.csv(ak_grid_stats,
          file.path(output_dir, "ak_grid_stats.csv"),
          row.names = FALSE)

cat("Outputs written to:", output_dir, "\n")
cat("\nDone:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
