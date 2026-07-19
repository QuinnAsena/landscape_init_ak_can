library(terra)
library(tidyr)
library(lubridate)
library(dplyr)
library(purrr)
library(DBI)
library(future.apply)
library(RSQLite)
library(here)


# Converts processed climate text files (from step 03) into SQLite databases
# for use by iLand. One database per landscape per GCM/SSP combination.
# Each table within the database corresponds to a single climate grid cell,
# named by the landscape_climate.grid convention used in the env.file.
# Based on Winslow's "climate_processing_step2.Rmd".
process_sqlite <- function(gcm, ssp, var, ak_landscape_dirs,
                           climate_subdir = "climate_link") {

  cat("\n\nprocessing: ", ak_landscape_dirs, gcm, ssp, "\n\n")

  out_dir <- here(ak_landscape_dirs, "databases")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  all_vars <- lapply(var, \(v) {
    ak_var_files <- list.files(
      here(ak_landscape_dirs, "supporting_data", climate_subdir, gcm, ssp, v),
      recursive = TRUE,
      full.names = TRUE,
      pattern = "\\.txt$")
    ak_climate_var_df <- do.call(rbind, lapply(ak_var_files, read.delim, sep = "\t", header = TRUE))
    ak_climate_var_df$date <- as.Date(ak_climate_var_df$date)
    ak_climate_var_df
  }) |>
    purrr::reduce(dplyr::left_join, by = join_by(climate.grid, date, gcm, ssp, landscape))

  all_vars <- all_vars |>
    mutate(
      vp = vp * 0.1,
      tasmax = tasmax - 273.15,
      tasmin  = tasmin - 273.15,
      rsds = pmax(rsds, 0),
      vp   = pmax(vp, 0),
      es_min =
        case_when(
          tasmin < 0 ~ 0.61078 * exp((21.875 * tasmin) / (tasmin + 265.5)),
           TRUE ~ 0.61078 * exp((17.269 * tasmin) / (tasmin + 237.3))),
      es_max =
        case_when(
          tasmax < 0 ~ 0.61078 * exp((21.875 * tasmax) / (tasmax + 265.5)),
           TRUE ~ 0.61078 * exp((17.269 * tasmax) / (tasmax + 237.3))),
      es = (es_min + es_max) / 2,
      vpd_calc = es - vp,
      vpd = pmax(vpd_calc, 0),
      across(where(is.numeric) & !any_of("climate.grid"), \(x) round(x, 2)),
      year = lubridate::year(date),
      month = lubridate::month(date),
      day = lubridate::day(date)
    ) |>
    tidyr::unite("model.climate.tableName", c(landscape, climate.grid), remove = TRUE) |>
    rename(max_temp = tasmax,
           min_temp = tasmin,
           rad = rsds,
           prec = pr) |>
    select(model.climate.tableName, year, month, day, min_temp, max_temp, prec, rad, vpd)

  db.conn <- dbConnect(RSQLite::SQLite(),
                       dbname = file.path(out_dir, paste0(gcm, ssp, ".sqlite")))
  on.exit(dbDisconnect(db.conn))

  split_data <- split(all_vars, all_vars$model.climate.tableName)

  lapply(names(split_data), \(nm) {
    dat <- split_data[[nm]] |> select(-model.climate.tableName)

    dbWriteTable(
      db.conn,
      name = nm,
      value = dat,
      row.names = FALSE,
      overwrite = TRUE
    )
  })

}


#--------------- Run the function ---------------#

# gcm <- c("NorEsm2-MM", "TaiESM1", "UKESM1-0-LL", "EC-Earth3-Veg", "GFDL-ESM4")
# ssp <- c("ssp126", "ssp245", "ssp370", "ssp585")
gcm <- "NorEsm2-MM"
# ssp <- "ssp126"
ssp <- c("ssp245", "ssp370")
# var <- c("tasmax", "hurs", "pr", "rsds", "tasmin", "vp")
var <- c("tasmax", "pr", "rsds", "tasmin", "vp")

dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])

param_grid <- expand.grid(
  landscape_dir = landscape_names,
  gcm  = gcm,
  ssp  = ssp,
  stringsAsFactors = FALSE
)

# I get memory issues running in parallel, setting workers = 1 for
