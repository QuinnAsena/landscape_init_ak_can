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


process_climate_link <- function(gcm, ssp, var, year, landscape_dir) {

  in_dir <- file.path(landscape_dir, "supporting_data", "climate")
  out_dir <- file.path(in_dir, gcm, ssp, var)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  ak_clim_in <- file.path("//10.60.2.10/FF_Lab/project_data/downscaling/Alaska", paste0("Downscaled CMIP6 ", gcm), ssp, var, paste0("CMIP6 ", gcm, "-", ssp, "-", var, "-", year, ".nc"))

  env_files <- list.files(path = file.path(landscape_dir, "gis"),
                        pattern = "env.grid.tif$", full.names = TRUE, recursive = TRUE)

  env_rast <- rast(env_files)
  ak_climate_var <- rast(ak_clim_in)

  # Polyfy landscape raster
  pol <- as.polygons(env_rast, extent = TRUE)
  env_points <- as.points(env_rast)
  # Buffer landscape area
  pol_buffer <- terra::buffer(pol, width = 4000)
  # Project to climate crs instead of projecting all ak to plot crs
  pol_buffer_daymetcrs <- project(pol_buffer, ak_climate_var)
  # Crop buffered landscape area from climate data
  pol_buffer_daymetcrs_crop <- crop(ak_climate_var, pol_buffer_daymetcrs) |>
    mask(pol_buffer_daymetcrs)
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

  pol_buffer_albers_crop_poly <- as.polygons(var_buffer_albers, dissolve = FALSE)

  # Create link data: col1 = env_rast cell id,
  climate_link <- terra::cells(var_buffer_albers, env_points) |>
    as.data.frame() |>
    rename(env.grid = "ID", climate.grid = "cell")
  head(climate_link)
  tail(climate_link)
  dim(climate_link)
  any(is.na(climate_link))

  write.table(ak_climate_var_df, file.path(in_dir, env.grid-climate.grid-link), row.names = FALSE)


  climate_extract <- terra::extract(var_buffer_albers, var_points_albers) |>
    as.data.frame() |>
    dplyr::rename(climate.grid = "ID") |>
    right_join(climate_link) |>
    distinct(climate.grid, .keep_all = TRUE) |>
    select(-env.grid)

  dim(climate_extract)
  head(climate_extract[,1:4])

  ak_climate_var_df <- climate_extract |>
    tidyr::pivot_longer(
      cols = -climate.grid,
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
