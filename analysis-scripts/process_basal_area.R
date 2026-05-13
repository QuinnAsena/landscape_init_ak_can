library(RSQLite)
library(DBI)
library(terra)
library(dplyr)
library(tidyr)

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

output_dir <- file.path(data_path, "processed", treatment, paste0("rep_", replicate), "basal_area")

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

dbconn <- DBI::dbConnect(
  RSQLite::SQLite(),
  dbname = input_file)

max_year <- tbl(dbconn, "stand") |>
  select(year) |>
  summarise(max_yr = max(year)) |>
  pull(max_yr, as_vector = TRUE)
dbDisconnect(dbconn)

cat(
  "--- process_basal_area ---\n",
  "landscape:  ", landscape, "\n",
  "treatment:  ", treatment, "\n",
  "replicate:  ", replicate, "\n",
  "input_file: ", input_file, "\n",
  "output_dir: ", output_dir, "\n",
  "max_year:   ", max_year, "\n",
  "start time: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n"
)

start_time <- Sys.time()

basal_area_processing_func <- function(input_file, fire_files, env_path) {
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

  # env.grid
  env_grid <- terra::rast(env_path)

  fire_maps <- terra::rast(fire_files)
  terra::crs(fire_maps) <- terra::crs(env_grid)

  fire_year_dat <- data.frame()
  for (i in seq_len(nrow(fire))) {
    # Skip fires that burned nothing
    if (fire$area_m2[i] > 0) {
      # Take the fire map for this fire, and make everything but the fire cells NA
      fire_mask <- fire_maps[[paste0("crownkill_", fire$fireId[i], "_", fire$year[i])]]
      fire_mask <- ifel(fire_mask == 0, NA, fire_mask)
      # Extract env_grid values (these are rid, not ru)
      burned_rids <- as.data.frame(mask(env_grid, fire_mask))
      names(burned_rids)[1] <- "rid"
      burned_rids <- burned_rids |> filter(!is.na(rid))
      burned_rids$year=fire$year[i]
    }
    fire_year_dat <- rbind(fire_year_dat, burned_rids)
  }
  fire_year_dat <- fire_year_dat |>
    rename("fire.year" = year)

  fire_year_dat <- fire_year_dat |>
    group_by(rid) |>
    summarize(last.fire.year = max(fire.year))


  stand <- tbl(dbconn, "stand") |>
    filter(ru != -1, year == max_year) |>
    dplyr::select(year, ru, rid, species, area_ha, count_ha, basal_area_m2) |>
    collect()

# Seems like it is much faster to filter if an index is added
#   DBI::dbGetQuery(dbconn, "PRAGMA index_list('saplingdetail')")
# But it took ages to add the index, so this is commented-out

  saplingdetail <- tbl(dbconn, "saplingdetail") |>
    filter(year == max_year) |>
    select(dbh, n_represented, rid, year, ru, species) |>
    mutate(
      ba = pi * ((dbh / 100) / 2)^2,
      ba_all = ba * n_represented) |>
    group_by(rid, year, ru, species) |>
    summarize(
      count_ha_sap = sum(n_represented),
      # dbh_mean_sapling = sum(dbh * n_represented) / sum(n_represented),
      ba_sum_sapling = sum(ba_all)) |>
    collect()

  # disconnect
  dbDisconnect(dbconn)

  cat("[basal_area] stand:", format(object.size(stand), units = "MB"),
      "| saplingdetail:", format(object.size(saplingdetail), units = "MB"), "\n")

  stand.t <- full_join(stand, saplingdetail, 
                       by = c("rid", "ru", "year", "species")) |>
    mutate(
      across(everything(), \(x) replace(x, is.na(x), 0)),
      count.total.ad.sap = count_ha + count_ha_sap,
      ba.total.ad.sap = basal_area_m2 + ba_sum_sapling) |>
    dplyr::select(
      ru, rid, year, species, area_ha,
      count.total.ad.sap:ba.total.ad.sap
    )

  stand.t.wide <- stand.t |>
    tidyr::pivot_wider(
      names_from = species,
      values_from = count.total.ad.sap:ba.total.ad.sap,
      values_fill = 0
    )

  rm(stand, saplingdetail, stand.t)
  gc()

  stand.t.wide <- stand.t.wide |>
    mutate(
      total.density.ad.sap =
        count.total.ad.sap_Potr + count.total.ad.sap_Pima +
        count.total.ad.sap_Bene + count.total.ad.sap_Pigl,
      total.ba.ad.sap =
        ba.total.ad.sap_Potr + ba.total.ad.sap_Pima +
        ba.total.ad.sap_Bene + ba.total.ad.sap_Pigl
    )

  stand.t.wide <- stand.t.wide |>
    mutate(
      IV.ad.sap_Pima = case_when(
        total.density.ad.sap != 0 & total.ba.ad.sap != 0 ~
          (count.total.ad.sap_Pima / total.density.ad.sap) +
            (ba.total.ad.sap_Pima / total.ba.ad.sap),
        TRUE ~ 0
      ),
      IV.ad.sap_Pigl = case_when(
        total.density.ad.sap != 0 & total.ba.ad.sap != 0 ~
          (count.total.ad.sap_Pigl / total.density.ad.sap) +
            (ba.total.ad.sap_Pigl / total.ba.ad.sap),
        TRUE ~ 0
      ),
      IV.ad.sap_Potr = case_when(
        total.density.ad.sap != 0 & total.ba.ad.sap != 0 ~
          (count.total.ad.sap_Potr / total.density.ad.sap) +
            (ba.total.ad.sap_Potr / total.ba.ad.sap),
        TRUE ~ 0
      ),
      IV.ad.sap_Bene = case_when(
        total.density.ad.sap != 0 & total.ba.ad.sap != 0 ~
          (count.total.ad.sap_Bene / total.density.ad.sap) +
            (ba.total.ad.sap_Bene / total.ba.ad.sap),
        TRUE ~ 0
      )
    )

  stand.t.wide <- stand.t.wide |>
    mutate(
      sp.dom = as.factor(case_when(
        IV.ad.sap_Pima > 1 ~ "Pima",
        IV.ad.sap_Potr > 1 ~ "Potr",
        IV.ad.sap_Pigl > 1 ~ "Pigl",
        IV.ad.sap_Bene > 1 ~ "Bene",
        IV.ad.sap_Pima < 1 & IV.ad.sap_Pigl < 1 & IV.ad.sap_Potr < 1 &
          IV.ad.sap_Bene < 1 & (IV.ad.sap_Pima + IV.ad.sap_Pigl) > 1
          ~ "Mixed.spruce",
        IV.ad.sap_Pima < 1 & IV.ad.sap_Pigl < 1 & IV.ad.sap_Potr < 1 &
          IV.ad.sap_Bene < 1 & (IV.ad.sap_Bene + IV.ad.sap_Potr) > 1
          ~ "Mixed.deciduous",
        TRUE ~ "Not forested"
      )),
      landscape = landscape,
      treatment = treatment,
      replicate = replicate
    )
  # Winslow's original script filters for stand age > 34, I will do this in post.
  stand.t.wide <- left_join(stand.t.wide, fire_year_dat, by = "rid") |>
    mutate(across(where(is.numeric), \(x) replace(x, is.na(x), 0))) |>
    mutate(stand.age = max_year - last.fire.year)

  cat(paste0("[basal_area] saving: basal_area_", max_year, ".parquet\n"))
  arrow::write_parquet(
    stand.t.wide,
    file.path(output_dir, paste0("basal_area_", max_year, ".parquet")),
    use_dictionary = FALSE
  )
  gc()
}

basal_area_processing_func(
    input_file = input_file, fire_files = fire_files, env_path = env_path)

cat(
  "\n--- Done ---\n",
  "elapsed:    ", format(Sys.time() - start_time), "\n",
  "output_dir: ", output_dir, "\n",
  "end time:   ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n"
)
