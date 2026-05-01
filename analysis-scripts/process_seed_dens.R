library(terra)
library(dplyr)
library(tidyr)
library(RSQLite)
library(DBI)
library(future.apply)
library(arrow)

args <- commandArgs(TRUE)
landscape <- args[1]
treatment <- args[2]
replicate <- as.numeric(args[3])

user <- "qasena"
data_path <- paste0("/glade/derecho/scratch/", user, "/output_ak_can/", landscape, "/")

input_file <- paste0(data_path, treatment, "/rep_",
                     replicate, "/", treatment, "_",
                     replicate, ".sqlite")

if (!file.exists(input_file)) stop("Input file not found: ", input_file)

# Check the existence of output directory.
# Will only print a warning if directory exists.

output_dir <- file.path(data_path, "processed", treatment, paste0("rep_", replicate), "seeddens")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

landscape_dir <- sub("^(landscape_[^_]+_\\d+)_.*", "\\1", landscape)
env_path <- paste0("/glade/work/qasena/landscape_init_ak_can/", landscape_dir, "/gis/env.grid.tif")

# Check if there are crownkill files to process
fire_files <- list.files(paste0(data_path, treatment,
                                "/rep_", replicate, "/crownkill/"),
                         full.names = TRUE)

if (length(fire_files) < 1) {
  stop("no crownkill files!")
}

cat(
  "--- process_seed_dens ---\n",
  "landscape:  ", landscape, "\n",
  "treatment:  ", treatment, "\n",
  "replicate:  ", replicate, "\n",
  "input_file: ", input_file, "\n",
  "output_dir: ", output_dir, "\n",
  "start time: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n"
)

# reading data -----------------------------------------------------------

dbconn <- DBI::dbConnect(
  RSQLite::SQLite(),
  dbname = input_file)

# Fire db
fire <- tbl(dbconn, "fire") |>
  collect()

fire <- fire |>
  mutate(prop.dens.killed = n_trees_died / n_trees,
         prop.ba.killed = basalArea_died / basalArea_total,
         area_ha = fire$area_m2 / 10000)

fire$prop.ba.killed[fire$basalArea_total == 0] <- 0
fire$prop.dens.killed[fire$n_trees == 0] <- 0

# Water db
water <- tbl(dbconn, "water") |>
  select(year, ru, rid, SOLLayer, mossLayer) |>
  collect()

year_range <- tbl(dbconn, "stand") |>
  select(year) |>
  summarise(min_yr = min(year),
            max_yr = max(year)) |>
  collect()

# disconnect
dbDisconnect(dbconn)

# env.grid
env_grid <- terra::rast(env_path)

# fire -------------------------------------------------------------------

fire_maps <- terra::rast(fire_files)
crs(fire_maps) <- crs(env_grid)

# Convert 0's to NA's
burnedArea <- subst(fire_maps, 0, NA, others = 1)
# Spatial raster collection of burned areas
burnedSRC <- terra::sprc(split(burnedArea, 1:nlyr(burnedArea)))

# All fire through time in single raster
fire_sum <- terra::mosaic(burnedSRC, fun = "min")
burned_rids_sum <- terra::values(terra::mask(env_grid, fire_sum))
burned_rids_sum <- burned_rids_sum[!is.na(burned_rids_sum)]

unburned_sum <- subst(fire_sum, 1, NA, others = 1)
unburned_rids_sum <- terra::values(terra::mask(env_grid, unburned_sum))
unburned_rids_sum <- unburned_rids_sum[!is.na(unburned_rids_sum)]

nfire <- terra::mosaic(burnedSRC, fun = "sum")
# burn1x <- terra::subst(nfire, 1, 1, others = NA)
# plot(burn1x)

# burn1x_inv <- terra::subst(nfire, 1, NA, others = 1)
# plot(nfire)

# One way to get rids of burn overlap
reburned_sum <- terra::subst(nfire, c(NA, 1), NA, others = 1)
reburned_rids_sum <- terra::values(terra::mask(env_grid, reburned_sum))
reburned_rids_sum <- reburned_rids_sum[!is.na(reburned_rids_sum), , drop = FALSE]
colnames(reburned_rids_sum)[1] <- "rid"

fire_sol_dat <- NULL
for (i in seq_len(nrow(fire))) {

  # Skip fires that burned nothing
  if (fire$area_m2[i] > 0) {

    # Take the fire map for this fire, and make everything but the fire cells NA
    fire_mask <- fire_maps[[paste0("crownkill_", fire$fireId[i], "_", fire$year[i])]]
    fire_mask <- ifel(fire_mask == 0, NA, fire_mask)

    # Use the mask to extract the rids for burned grids
    burned_rids <- terra::values(terra::mask(env_grid, fire_mask))
    burned_rids <- burned_rids[!is.na(burned_rids)]

    if (length(burned_rids) > 0) { # should never happen but...

      # Years we want info: year before the fire, through 60 years post-fire
      fire_years <- (fire$year[i] - 1):(fire$year[i] + 60)

      firedat <- water |> 
        filter(year %in% fire_years &
                 rid %in% burned_rids)

      firedat$prop.dens.killed <- fire$prop.dens.killed[i]
      firedat$prop.ba.killed <- fire$prop.ba.killed[i]

      # Add the year of the record relative to the fire, and soil organic layer
      # thickness (go from m to cm)
      firedat <- firedat |>
        mutate(rel.year  = year - fire$year[i],
               fireId    = fire$fireId[i],
               fire.year = fire$year[i],
               SOLLayer  = ifelse(is.na(SOLLayer), 0, SOLLayer),
               mossLayer = ifelse(is.na(mossLayer), 0, mossLayer),
               SOL.cm    = SOLLayer * 100 + mossLayer * 100)

      firedat <- firedat |>
        dplyr::select(year, ru, rid,
                      fireId, rel.year,
                      fire.year,
                      SOLLayer, mossLayer,
                      SOL.cm,
                      prop.dens.killed,
                      prop.ba.killed)

      fire_sol_dat <- rbind(fire_sol_dat, firedat)

    } else {
      stop("Better check on this...")
    }
  }
}

# For now we do not need unburned area
# nofire_sol_dat <- water |> 
#   filter(rid %in% unburned_rids_sum) |> 
#   mutate(
#     SOLLayer = ifelse(is.na(SOLLayer), 0, SOLLayer),
#     SOL.cm = SOLLayer * 100 + mossLayer * 100
#   ) |>
#   dplyr::select(year, ru, rid, SOL.cm)

years <- year_range$min_yr:year_range$max_yr

keep <- c("fire_sol_dat", "input_file", "burned_rids_sum",
          "reburned_rids_sum", "landscape", "treatment", "replicate", "output_dir", "years")
rm(list = setdiff(ls(), keep))
gc()

# Stand and sapling ------------------------------------------------------

process_chunk <- function(start, end) {
  # end <- start + (span -1)

  dbconn <- DBI::dbConnect(
    RSQLite::SQLite(),
    dbname = input_file)

  # Filtering by burned rid. Lora's original script keeps both burned and unburned
  stand <- tbl(dbconn, "stand") |>
    dplyr::filter(year %in% start:end,
                  rid %in% burned_rids_sum) |>
    dplyr::select(year, ru, rid, species, area_ha, count_ha, basal_area_m2) |>
    collect()

  sapling <- tbl(dbconn, "sapling") |>
    filter(year %in% start:end,
           rid %in% burned_rids_sum) |>
    dplyr::select(
      ru, year, species, rid,
      "sapling_count_ha" = count_ha,
      "sapling_count_ha_small" = count_small_ha
    ) |>
    collect()

  # Query the database
  sapling.detail <- tbl(dbconn, "saplingdetail") |>
    filter(year %in% start:end, rid %in% burned_rids_sum) |>
    select(dbh, n_represented, rid, year, ru, species) |>
    mutate(basal.area.ind = pi * ((dbh / 100) / 2)^2,
           basal.area.cohort = basal.area.ind * n_represented) |>
    group_by(year, ru, rid, species) |>
    summarize(
      # dbh_mean = sum(dbh * n_represented) / sum(n_represented),
      basal.area.total = sum(basal.area.cohort),
      .groups = "drop") |>
    collect()

  # Disconnect from the database
  DBI::dbDisconnect(dbconn)

  cat(paste0("[", start, "-", end, "] stand: ", format(object.size(stand), units = "MB"),
             " | sapling: ", format(object.size(sapling), units = "MB"),
             " | sapling.detail: ", format(object.size(sapling.detail), units = "MB"), "\n"))

  # Join all this up
  stand.sap.1 <- full_join(stand, sapling.detail, by = c("rid", "ru", "year", "species"))
  final.trees <- full_join(stand.sap.1, sapling, by = c("rid",  "ru", "year", "species"))
  final.trees <- final.trees |> 
    mutate(across(everything(), \(x) replace(x, is.na(x), 0)))

  rm(stand, sapling.detail, stand.sap.1, sapling)
  gc()
  # Total density and basal area sums; this here will be by species
  final.trees <- final.trees |>
    mutate(
      count_total = count_ha + sapling_count_ha + sapling_count_ha_small,
      basal.area_sum = basal_area_m2 + basal.area.total
    )

  # Widen table so each record has all species in it
  final.trees.wide <- final.trees |>
    tidyr::pivot_wider(
      names_from = species, names_sep = ".",
      values_from = c(count_ha:basal.area_sum), values_fill = 0
    )

  # Final sums across species
  final.trees.wide <- final.trees.wide |>
    mutate(
      total_density =
        count_total.Potr + count_total.Pima +
        count_total.Bene + count_total.Pigl,
      total_ba =
        basal.area_sum.Potr + basal.area_sum.Pima +
        basal.area_sum.Bene + basal.area_sum.Pigl
    )

  # Final importance value
    final.trees.wide <- final.trees.wide |>
      mutate(
        IV.Pima = case_when(
          total_density != 0 & total_ba != 0 ~ (count_total.Pima / total_density) +
                                               (basal.area_sum.Pima / total_ba),
          TRUE ~ 0
        ),
        IV.Pigl = case_when(
          total_density != 0 & total_ba != 0 ~ (count_total.Pigl / total_density) +
                                               (basal.area_sum.Pigl / total_ba),
          TRUE ~ 0
        ),
        IV.Potr = case_when(
          total_density != 0 & total_ba != 0 ~ (count_total.Potr / total_density) +
                                               (basal.area_sum.Potr / total_ba),
          TRUE ~ 0
        ),
        IV.Bene = case_when(
          total_density != 0 & total_ba != 0 ~ (count_total.Bene / total_density) +
                                               (basal.area_sum.Bene / total_ba),
          TRUE ~ 0
        )
      )

  # Assign a stand type by whatever is the species with the highest IV
  iv_cols <- grep("IV", names(final.trees.wide))
  spp <- sapply(names(final.trees.wide)[iv_cols], function(x){strsplit(x, ".", fixed=T)[[1]][2]})
  ind <- apply(final.trees.wide[,iv_cols], MARGIN = 1, FUN = which.max)
  final.trees.wide$stand.type <- as.factor(spp[ind])

  cat(paste0("[", start, "-", end, "] final.trees.wide: ", format(object.size(final.trees.wide), units = "MB"), "\n"))
  cat(paste0("[", start, "-", end, "] saving: chunk_", start, "_fire_sol_trees.parquet\n"))

  rm(final.trees)
  gc()
  # We want to make sure we are looking at stand type at the right time. This will
  # give us the stand info along each year.
  fire_sol_trees <- fire_sol_dat |>
    filter(year %in% final.trees.wide$year) |>
    left_join(final.trees.wide, by = c("rid", "ru", "year"))
  # Append rids that burned more than once for later filtering
  fire_sol_trees <- fire_sol_trees |>
    left_join(as_tibble(reburned_rids_sum))

  fire_sol_trees <- fire_sol_trees |>
    mutate(landscape = landscape,
           treatment = treatment,
           replicate = replicate)

  arrow::write_parquet(
    fire_sol_trees,
    file.path(output_dir, paste0("chunk_", start, "_fire_sol_trees.parquet"))
  )
}


start_time_par <- Sys.time()
# Define range of years
span <- 10
year_chunks <- seq(from = min(years), to = max(years), by = span)
chunk_ends <- pmin(year_chunks + span - 1, max(years))
chunks <- data.frame(start = year_chunks, end = chunk_ends)

# Set up parallel processing (adjust workers as needed)
if (nrow(chunks) > 5) {
  cpus <- 5
} else {
  cpus <- nrow(chunks)
}

cat("Processing", nrow(chunks), "year chunks with", cpus, "workers:\n")
print(chunks)

plan(multicore, workers = cpus)
options(future.globals.maxSize = 1 * 1024^3)
# Run the processing in parallel for each chunk
sapling.detail.sum <- future.apply::future_lapply(1:nrow(chunks), function(i) {
  process_chunk(chunks$start[i], chunks$end[i])
})

# Reset future plan to sequential after execution
plan(sequential)

gc()

end_time_par <- Sys.time()
cat(
  "\n--- Done ---\n",
  "elapsed:    ", format(end_time_par - start_time_par), "\n",
  "output_dir: ", output_dir, "\n",
  "end time:   ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n"
)
