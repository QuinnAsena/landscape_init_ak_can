library(terra)
library(sf)
# library(tidyr)
library(lubridate)
library(dplyr)
library(purrr)
library(DBI)
library(future.apply)


process_sqlite <- function(gcm, ssp, var, ak_landscape_dirs) {

  out_dir <- file.path(ak_landscape_dirs, "databases")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  all_vars <- lapply(var, \(v) {
    # ak_var_files <- list.files(file.path(ak_processed_climate_dirs, gcm, ssp, v), recursive = TRUE, full.names = TRUE, pattern = "\\.txt$")
    ak_var_files <- list.files(
      file.path(ak_landscape_dirs, "climate", gcm, ssp, v),
      recursive = TRUE,
      full.names = TRUE,
      pattern = "\\.txt$")
    ak_climate_var_df <- do.call(rbind, lapply(ak_var_files, read.delim, sep = "\t", header = TRUE))
    ak_climate_var_df$date <- as.Date(ak_climate_var_df$date)
    ak_climate_var_df
  }) |>
    purrr::reduce(dplyr::left_join, by = join_by(climate.gridCell, date, gcm, ssp, landscape))

  head(all_vars)
  tail(all_vars)

  all_vars <- all_vars |>
    mutate(
      vp = vp * 0.1,
      tasmax = tasmax - 273.15,
      tasmin  = tasmin - 273.15,
      rsds = case_when(
          rsds < 0 ~ 0, TRUE ~ rsds),
      vp = case_when(
          vp < 0 ~ 0, TRUE ~ vp),
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
      vpd = 
        case_when(
          vpd_calc > 0 ~ vpd_calc,
           TRUE ~ 0),
      across(where(is.numeric), \(x) round(x, 2)), # Winslow's code only rounds rad and vpd
      year = lubridate::year(date),
      month = lubridate::month(date),
      day = lubridate::day(date)
    ) |>
    unite("model.climate.tableName", c(landscape, climate.gridCell), remove = TRUE) |>
    rename(max_temp = tasmax,
           min_temp = tasmin,
           rad = rsds,
           prec = pr) |>
    select(model.climate.tableName, year, month, day, min_temp, max_temp, prec, rad, vpd)



  db.conn <- dbConnect(RSQLite::SQLite(),
                       dbname = file.path(out_dir, paste0(gcm, ssp, "V3.sqlite")))

  split_data <- split(all_vars, all_vars$model.climate.tableName)

  lapply(names(split_data), \(nm) {
    dat <- split_data[[nm]]
    dat <- dat |>
      select(-model.climate.tableName)

    dbWriteTable(
      db.conn,
      name = nm,
      value = dat,
      row.names = FALSE,
      overwrite = TRUE
    )
  })

  dbDisconnect(db.conn)
}

gcm <- "NorEsm2-MM"
ssp <- "ssp126"
var <- c("tasmax", "hurs", "pr", "rsds", "tasmin", "vp")

dirs <- normalizePath(list.dirs(full.names = TRUE))
ak_landscape_dirs <- dirs[grepl(".*[\\\\/]landscape_[0-9]+$", dirs)]

# make sure landscapes are ordered
landscape_id <- as.integer(
  sub(".*landscape_([0-9]+)$", "\\1", ak_landscape_dirs)
)
ord <- order(landscape_id)
ak_landscape_dirs <- ak_landscape_dirs[ord]
landscape_id    <- landscape_id[ord]

ak_landscapes_df <- data.frame(
  landscape = landscape_id,
  ak_landscape_dirs = ak_landscape_dirs
)

# stringsAsFactors = FALSE needed for "var" names
param_grid <- base::merge(
  expand.grid(
    landscape = landscape_id,
    gcm  = gcm,
    ssp  = ssp,
    stringsAsFactors = FALSE
  ),
  ak_landscapes_df,
  by = "landscape"
)


plan(multisession, workers = 5)

res <- future_lapply(
  seq_len(nrow(param_grid)),
  function(i) {
    process_sqlite(
      gcm  = param_grid$gcm[i],
      ssp  = param_grid$ssp[i],
      var  = var,
      ak_landscape_dirs = param_grid$ak_landscape_dirs[i]
    )
  },
  future.seed = TRUE
)
plan(sequential)
