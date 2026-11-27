library(terra)
library(dplyr)
library(RSQLite)
library(DBI)
library(arrow)

args <- commandArgs(TRUE)
landscape <- args[1] # "landscape_alaska_01_2015-2100scenario"
treatment <- args[2] # "NorEsm2-MMssp245_dbh2.5_onlysimfalse_fri10"
replicate <- as.numeric(args[3]) # 2

user <- "qasena"
data_path <- paste0("/glade/derecho/scratch/", user, "/output_ak_can/", landscape, "/")

input_file <- paste0(data_path, treatment, "/rep_",
                     replicate, "/", treatment, "_",
                     replicate, ".sqlite")

if (!file.exists(input_file)) stop("Input file not found: ", input_file)

output_dir <- file.path(data_path, "processed", treatment, paste0("rep_", replicate), "burned_rids")
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

# Soil organic layer and moss are read at these offsets from the fire year. pre
# is the baseline, yr0 is immediately post-fire, yr1..yr10 the recovery window.
sol_offsets <- c(pre = -1, setNames(0:10, paste0("yr", 0:10)),
                 yr15 = 15, yr20 = 20, yr25 = 25, yr30 = 30, yr35 = 35, yr40 = 40, yr45 = 45, yr50 = 50)

cat(
  "--- process_burned_rids ---\n",
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
  select(year, fireId, area_m2) |>
  collect()

# Water db -- soil organic layer and moss, per rid per year
water <- tbl(dbconn, "water") |>
  select(year, rid, SOLLayer, mossLayer) |>
  collect()

# disconnect
dbDisconnect(dbconn)

# env.grid
env_grid <- terra::rast(env_path)

# fire -------------------------------------------------------------------

fire_maps <- terra::rast(fire_files)
crs(fire_maps) <- crs(env_grid)

burned_dat <- NULL
for (i in seq_len(nrow(fire))) {

  # Skip fires that burned nothing
  if (fire$area_m2[i] > 0) {

    lyr <- paste0("crownkill_", fire$fireId[i], "_", fire$year[i])
    if (!lyr %in% names(fire_maps)) {
      stop("no crownkill layer named ", lyr, " -- check the file naming")
    }

    fire_mask <- fire_maps[[lyr]]
    fire_mask <- ifel(fire_mask == 0, NA, fire_mask)

    burned_rids <- terra::values(terra::mask(env_grid, fire_mask))
    burned_ck   <- terra::values(fire_mask)
    keep        <- !is.na(burned_rids)

    if (any(keep)) { # should never happen but...

      firedat <- data.frame(
        rid       = burned_rids[keep],
        crownkill = burned_ck[keep],
        fireId    = fire$fireId[i],
        year      = fire$year[i]
      )

      burned_dat <- rbind(burned_dat, firedat)

    } else {
      stop("Better check on this...")
    }
  }
}

# soil organic layer -----------------------------------------------------

if (is.null(burned_dat)) {
  # Ran, but nothing burned. Write the empty table anyway, so a replicate that
  # never burned stays distinguishable from one that was never processed.
  burned_dat <- data.frame(rid = numeric(0), crownkill = numeric(0),
                           fireId = numeric(0), year = numeric(0),
                           gap_to_next = numeric(0), gap_from_prev = numeric(0))
  for (nm in names(sol_offsets)) {
    burned_dat[[paste0("sol_", nm)]]  <- numeric(0)
    burned_dat[[paste0("moss_", nm)]] <- numeric(0)
  }
} else {
  burned_dat <- burned_dat |>
    arrange(rid, year) |>
    group_by(rid) |>
    mutate(gap_to_next   = coalesce(lead(year) - year, Inf),
           gap_from_prev = year - lag(year)) |>
    ungroup()

  for (nm in names(sol_offsets)) {
    w <- water
    names(w) <- c("join_year", "rid", paste0("sol_", nm), paste0("moss_", nm))
    burned_dat$join_year <- burned_dat$year + sol_offsets[[nm]]
    burned_dat <- left_join(burned_dat, w, by = c("rid", "join_year"),
                            relationship = "many-to-one")
    burned_dat$join_year <- NULL
  }
}

burned_dat <- burned_dat |>
  mutate(landscape = landscape,
         treatment = treatment,
         replicate = replicate)

# Write under a temporary name, then rename: a rename is atomic, so burned_rids.parquet
# only ever exists complete. run_fire_sol.sh treats its existence as "this replicate is
# done", so a run killed mid-write (walltime, Ctrl-C) must not leave a truncated file
# under the final name -- it leaves only the .tmp, and the replicate is redone next time.
out_file <- file.path(output_dir, "burned_rids.parquet")
tmp_file <- paste0(out_file, ".tmp")
arrow::write_parquet(burned_dat, tmp_file)
if (!file.rename(tmp_file, out_file)) stop("could not rename ", tmp_file, " to ", out_file)

cat(
  "\n--- Done ---\n",
  "fires:      ", sum(fire$area_m2 > 0), " of ", nrow(fire), " logged\n",
  "rows:       ", nrow(burned_dat), "\n",
  "rids:       ", length(unique(burned_dat$rid)), " distinct burned\n",
  "sol NA:     ", paste(names(sol_offsets),
                        sapply(paste0("sol_", names(sol_offsets)),
                               function(x) sum(is.na(burned_dat[[x]]))),
                        sep = "=", collapse = " "), "\n",
  "output_dir: ", output_dir, "\n",
  "end time:   ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n"
)
