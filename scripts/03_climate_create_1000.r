library(terra)
library(sf)
library(tidyr)
library(dplyr)
library(lubridate)
library(future.apply)
library(here)

dirs <- list.dirs(here(), recursive = FALSE)
landscape_dirs <- dirs[grepl("landscape_", basename(dirs))]
landscape_names <- basename(landscape_dirs)

# above_study_domain_file <- list.files(
#   "//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/ABoVE_reference_grid_v2_1527/data",
#   pattern = "\\.tif$", full.names = TRUE)

# above_study_domain <- rast(above_study_domain_file)
# plot(above_study_domain)
# crs(above_study_domain)

# This script converts Winslow's "climate_processing_step1.Rmd"
# Load one layer of the whole of Alaska as a template to crop landcapes
ak_climate <- rast(
  "//10.60.2.10/FF_Lab/project_data/downscaling/Alaska/Downscaled CMIP6 NorESM2-MM/ssp126/tasmax/CMIP6 NorESM2-MM-ssp126-tasmax-2015.nc",
  lyrs = 4)
# plot(ak_climate)
# Load env.grid files (careful of crs here, they are in ESRI:102001)

# ak_climate_to_above <- project(ak_climate, crs(above_study_domain))
# writeRaster(ak_climate_to_above, file.path(here("data"), "ak_climate_to_above.tif"),
#             overwrite = TRUE)


process_climate <- function(gcm, ssp, var, year, landscape_dir) {

  in_dir <- file.path(landscape_dir, "supporting_data", "climate")
  out_dir <- file.path(in_dir, gcm, ssp, var)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  ak_clim_in <- file.path("//10.60.2.10/FF_Lab/project_data/downscaling/Alaska", paste0("Downscaled CMIP6 ", gcm), ssp, var, paste0("CMIP6 ", gcm, "-", ssp, "-", var, "-", year, ".nc"))

  env_files <- list.files(path = file.path(landscape_dir, "gis"),
                        pattern = "env.grid.tif$", full.names = TRUE, recursive = TRUE)

  env_rast <- rast(env_files)
  ak_climate_var <- rast(ak_clim_in)

  plot(env_rast)
  # Polyfy landscape raster
  pol <- as.polygons(env_rast, extent = TRUE)
  pol_env <- as.polygons(env_rast)
  env_points <- as.points(env_rast)
  plot(pol_env)
  # Buffer landscape area
  pol_buffer <- terra::buffer(pol, width = 4000)
  plot(pol_buffer)
  # Project to climate crs instead of projecting all ak to plot crs
  pol_buffer_daymetcrs <- project(pol_buffer, ak_climate_var)
  plot(pol_buffer_daymetcrs)
  # Crop buffered landscape area from climate data
  pol_buffer_daymetcrs_crop <- crop(ak_climate_var, pol_buffer_daymetcrs) |>
    mask(pol_buffer_daymetcrs)
  plot(pol_buffer_daymetcrs_crop)
  # Turn buffered area into a grid

  # pol_buffer_daymetcrs_crop_poly <- as.polygons(pol_buffer_daymetcrs_crop, dissolve = FALSE)
  # plot(pol_buffer_daymetcrs_crop_poly)

  # Project back to equal albers
  var_buffer_albers <- project(pol_buffer_daymetcrs_crop, crs(env_rast))
  plot(var_buffer_albers)

  if (all(grepl("rsds", names(var_buffer_albers)))) {
    var_buffer_albers <- (var_buffer_albers * 86400) / 1000000
  }

  if (all(grepl("vp", names(var_buffer_albers)))) {
    vp_names <- paste0("vp_", seq_len(nlyr(var_buffer_albers)))
    if (!identical(names(var_buffer_albers), vp_names)) {
      names(var_buffer_albers) <- vp_names
    }
  }
  var_points_albers <- as.points(var_buffer_albers)
  plot(var_points_albers)
  pol_buffer_albers_crop_poly <- as.polygons(var_buffer_albers, dissolve = FALSE)
  plot(pol_buffer_albers_crop_poly)
  plot(env_rast, add = TRUE)
  # Create link data: col1 = env_rast cell id,
  # climate_link <- terra::cells(is.na(env_rast), pol_buffer_albers_crop_poly)
  # climate_link <- na.omit(climate_link)
  # climate_link <- terra::cells(var_buffer_albers, pol_env, touches = FALSE)
  climate_link <- terra::cells(var_buffer_albers, env_points)
  head(climate_link)
  tail(climate_link)
  dim(climate_link)
  any(is.na(climate_link))

  climate_extract <- terra::extract(var_buffer_albers, env_points) |>
    as.data.frame() |>
    dplyr::rename(env.grid = "ID")


  ak_climate_var_df <- climate_extract |>
    tidyr::pivot_longer(
      cols = -env.grid,
      names_to = "y_day",
      values_to = "value") |>
    dplyr::mutate(
      y_day = as.numeric(sub(paste0(var, "_"), "", y_day)),
      day_of_year = ifelse(lubridate::leap_year(year) & y_day >= 60, y_day + 1, y_day),
      date = lubridate::make_date(year) + lubridate::days(day_of_year - 1),
      value = round(value, 3),
      gcm = gcm,
      ssp = ssp,
      landscape = basename(landscape_dir)) |>
    dplyr::select(climate.grid, value, date, gcm, ssp, landscape) |>
    dplyr::rename(!!var := value)
    # names(df)[names(df) == "value"] <- var # for base R rename. no tidy evaluation. 
  write.table(ak_climate_var_df, file.path(out_dir, paste0(gcm, "-", ssp, "-", var, "-", year, ".txt")), row.names = FALSE, sep = "\t")
}


# --------- Parallel processing for multiple files --------
gcm <- "NorEsm2-MM"
# ssp <- "ssp126"
ssp <- "historical"
var <- c("tasmax", "hurs", "pr", "rsds", "tasmin", "vp")
year <- 2015:2016

dirs <- list.dirs(here(), recursive = FALSE)
landscape_dirs <- dirs[grepl("landscape_", basename(dirs))]
landscape_names <- basename(landscape_dirs)
landscape_out_dirs <- file.path(landscape_dirs, "supporting_data", "climate")

param_grid <- expand.grid(
  landscape_dir = landscape_names,
  gcm  = gcm,
  ssp  = ssp,
  var  = var,
  year = year,
  stringsAsFactors = FALSE
)


plan(multisession, workers = 21)

res <- future_lapply(
  seq_len(nrow(param_grid)),
  function(i) {
    process_climate(
      gcm  = param_grid$gcm[i],
      ssp  = param_grid$ssp[i],
      var  = param_grid$var[i],
      year = param_grid$year[i],
      landscape_dir = param_grid$landscape_dir[i]
    )
  },
  future.seed = TRUE
)
plan(sequential)














dirs <- normalizePath(list.dirs(full.names = TRUE))
ak_climate_dirs <- dirs[grepl(".*[\\\\/]landscape_[0-9]+[\\\\/]climate$", dirs)]
 # make sure landscapes are ordered
landscape_id <- as.integer(
  sub(".*landscape_([0-9]+)[\\\\/]climate$", "\\1", ak_climate_dirs)
)
ord <- order(landscape_id)
ak_climate_dirs <- ak_climate_dirs[ord]
landscape_id    <- landscape_id[ord]

ak_climate_df <- data.frame(
  landscape = landscape_id,
  ak_climate_dirs = ak_climate_dirs
)

# stringsAsFactors = FALSE needed for "var" names
param_grid <- left_join(
  expand.grid(
    landscape = landscape_id,
    gcm  = gcm,
    ssp  = ssp,
    var  = var,
    year = year,
    stringsAsFactors = FALSE
  ),
  ak_climate_df,
  by = "landscape"
)

library(future.apply)

plan(multisession, workers = 6)

res <- future_lapply(
  seq_len(nrow(param_grid)),
  function(i) {
    process_climate(
      gcm  = param_grid$gcm[i],
      ssp  = param_grid$ssp[i],
      var  = param_grid$var[i],
      year = param_grid$year[i],
      ak_climate_dirs = param_grid$ak_climate_dirs[i]
    )
  },
  future.seed = TRUE
)
plan(sequential)
