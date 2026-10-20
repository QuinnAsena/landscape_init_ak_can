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

  var_dfs <- lapply(var, \(v) {
    ak_var_files <- list.files(
      here(ak_landscape_dirs, "supporting_data", climate_subdir, gcm, ssp, v),
      recursive = TRUE,
      full.names = TRUE,
      pattern = "\\.txt$")
    ak_climate_var_df <- do.call(rbind, lapply(ak_var_files, read.delim, sep = "\t", header = TRUE))
    if (is.null(ak_climate_var_df) || !nrow(ak_climate_var_df))
      stop(sprintf("no climate_link .txt files for %s / %s / %s / %s -- run script 03 first",
                   ak_landscape_dirs, gcm, ssp, v), call. = FALSE)
    ak_climate_var_df$date <- as.Date(ak_climate_var_df$date)
    ak_climate_var_df
  })
  names(var_dfs) <- var

  # GUARD: every variable must cover the same years before anything is joined.
  #
  # The join below is a LEFT join anchored on the first variable, so a variable
  # that is short a year does not drop the row -- it fills that column with NA,
  # which lands in the database as a whole year of NULLs. That is exactly how
  # three corrupt NorEsm2-MM/ssp245 source files went unnoticed until the data
  # was plotted months later. Stop here instead, naming what is missing.
  year_sets <- lapply(var_dfs, \(d) sort(unique(lubridate::year(d$date))))
  all_years <- sort(unique(unlist(year_sets)))
  short <- vapply(year_sets, \(ys) length(setdiff(all_years, ys)) > 0, logical(1))
  if (any(short)) {
    detail <- vapply(names(year_sets)[short], \(v) sprintf("    %s missing: %s", v,
                       paste(setdiff(all_years, year_sets[[v]]), collapse = ", ")), character(1))
    stop(sprintf("climate variables disagree on years for %s / %s / %s:\n%s\n  Fix the source .nc and re-run script 03 (with logs = TRUE) before compiling.",
                 ak_landscape_dirs, gcm, ssp, paste(detail, collapse = "\n")), call. = FALSE)
  }

  all_vars <- var_dfs |>
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

  # GUARD: no NA may reach the database, whatever produced it.
  #
  # Deliberately separate from the year-set check above. That one catches a
  # variable short of a whole year; this one catches NA *content* inside a file
  # that exists -- e.g. NorEsm2-MM/ssp245 vp-1958, which is full size with a valid
  # CRS but all-NA over the Landscapes domain, so the year is present and the
  # values are not. It also covers anything the derivation introduces: vpd is
  # es(tasmin, tasmax) - vp, so it inherits an NA from either input.
  clim_cols <- c("min_temp", "max_temp", "prec", "rad", "vpd")
  na_counts <- vapply(all_vars[clim_cols], \(x) sum(is.na(x)), integer(1))
  if (any(na_counts > 0)) {
    detail <- vapply(names(na_counts)[na_counts > 0], \(cn) {
      yrs <- sort(unique(all_vars$year[is.na(all_vars[[cn]])]))
      sprintf("    %s: %d NA in year(s) %s", cn, na_counts[[cn]], paste(yrs, collapse = ", "))
    }, character(1))
    stop(sprintf("NA values in compiled climate for %s / %s / %s -- refusing to write the database:\n%s",
                 ak_landscape_dirs, gcm, ssp, paste(detail, collapse = "\n")), call. = FALSE)
  }

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

# I get memory issues running in parallel, setting workers = 1 for now.
plan(multisession, workers = 2)

future_lapply(
  seq_len(nrow(param_grid)),
  function(i) {
    process_sqlite(
      gcm  = param_grid$gcm[i],
      ssp  = param_grid$ssp[i],
      var = var,
      ak_landscape_dirs = param_grid$landscape_dir[i],
      climate_subdir = "climate_link"
    )
  },
  future.seed = TRUE
)
plan(sequential)
