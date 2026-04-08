library(terra)
library(tidyr)
library(dplyr)
library(lubridate)
library(future.apply)
library(here)

dirs <- list.dirs(here(), recursive = FALSE)
landscape_dirs <- dirs[grepl("landscape_", basename(dirs))]
landscape_names <- basename(landscape_dirs)

gcm <- "NorEsm2-MM"
ssp <- "ssp126"
var <- c("tasmax", "hurs", "pr", "rsds", "tasmin", "vp")
year <- 1950:2100

param_grid <- expand.grid(
  landscape_dir = landscape_names,
  gcm  = gcm,
  ssp  = ssp,
  var  = var,
  year = year,
  stringsAsFactors = FALSE
)

# Both functions handle the mismatch between the ~1000x1000m climate grid and
# the 100x100m RU grid, which causes partial-cell overlaps at landscape edges.

# process_climate: reprojects and interpolates climate data to 100x100m to
# match the RU resolution exactly. Output row count equals the number of RUs.

process_climate <- function(gcm, ssp, var, year, landscape_dir) {

  in_dir <- here(landscape_dir, "supporting_data", "climate")
  out_dir <- file.path(in_dir, gcm, ssp, var)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  clim_in <- file.path("//10.60.2.10/FF_Lab/project_data/downscaling/Landscapes",
    paste0("Downscaled ", gcm), ssp, var,
    paste0(gcm, "-", ssp, "-", var, "-", year, ".nc"))
  cpcrw_clim_in <- file.path("//10.60.2.10/FF_Lab/project_data/downscaling/CPCRW",
    paste0("Downscaled ", gcm), ssp, var,
    paste0(gcm, "-", ssp, "-", var, "-", year, ".nc"))

  env_files <- list.files(path = here(landscape_dir, "gis"),
                          pattern = "env.grid.tif$", full.names = TRUE, recursive = TRUE)

  ak_climate_var <- rast(clim_in)
  env_grid <- rast(env_files)

  # Fall back to the CPCRW climate dataset if the landscape lies outside the
  # standard regional domain (e.g. CPCRW is not covered by the Landscapes files)
  env_ext_clim_crs <- project(ext(env_grid), from = crs(env_grid), to = crs(ak_climate_var))
  if (all(is.na(values(crop(ak_climate_var[[1]], env_ext_clim_crs))))) {
    ak_climate_var <- rast(cpcrw_clim_in)
  }

  env_grid_sp <- as.points(env_grid, values = TRUE, na.rm = TRUE)

  ak_climate_var_proj <- project(ak_climate_var, env_grid, method = "bilinear")

  if (all(grepl("rsds", names(ak_climate_var_proj)))) {
    ak_climate_var_proj <- (ak_climate_var_proj * 86400) / 1000000
  }

  if (all(grepl("vp", names(ak_climate_var_proj)))) {
    vp_names <- paste0("vp_", seq_len(nlyr(ak_climate_var_proj)))
    if (!identical(names(ak_climate_var_proj), vp_names)) {
      names(ak_climate_var_proj) <- vp_names
    }
  }

  ak_climate_var_df <- as.data.frame(terra::extract(ak_climate_var_proj, env_grid_sp, bind = TRUE)) |>
    rename("climate.grid" = ru)

  ak_climate_var_df <- ak_climate_var_df |>
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
      landscape = landscape_dir) |>
    dplyr::select(climate.grid, value, date, gcm, ssp, landscape) |>
    dplyr::rename(!!var := value)
    # names(df)[names(df) == "value"] <- var # for base R rename. no tidy evaluation. 
  write.table(ak_climate_var_df, file.path(out_dir, paste0(gcm, "-", ssp, "-", var, "-", year, ".txt")), row.names = FALSE, sep = "\t")
}


# --------- Parallel processing for multiple files --------
# plan(multisession, workers = 6)

# res <- future_lapply(
#   seq_len(nrow(param_grid)),
#   function(i) {
#     process_climate(
#       gcm  = param_grid$gcm[i],
#       ssp  = param_grid$ssp[i],
#       var  = param_grid$var[i],
#       year = param_grid$year[i],
#       landscape_dir = param_grid$landscape_dir[i]
#     )
#   },
#   future.seed = TRUE
# )
# plan(sequential)




# --------------------------------------------------------- #
# ---------  Process climate with buffer and link  -------- #
# --------------------------------------------------------- #

# process_climate_link: buffers the landscape, crops the raw 1000x1000m climate
# data to that buffered area, then creates a lookup table linking each RU cell
# to its corresponding climate grid cell. This avoids reprojecting the full
# climate dataset and preserves the native climate resolution.

process_climate_link <- function(gcm, ssp, var, year, landscape_dir) {

  in_dir <- here(landscape_dir, "supporting_data", "climate_link")
  out_dir <- file.path(in_dir, gcm, ssp, var)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  clim_in <- file.path("//10.60.2.10/FF_Lab/project_data/downscaling/Landscapes",
    paste0("Downscaled ", gcm), ssp, var,
    paste0(gcm, "-", ssp, "-", var, "-", year, ".nc"))
  cpcrw_clim_in <- file.path("//10.60.2.10/FF_Lab/project_data/downscaling/CPCRW",
    paste0("Downscaled ", gcm), ssp, var,
    paste0(gcm, "-", ssp, "-", var, "-", year, ".nc"))

  env_files <- list.files(path = here(landscape_dir, "gis"),
                        pattern = "env.grid.tif$", full.names = TRUE, recursive = TRUE)

  env_rast <- rast(env_files)
  ak_climate_var <- rast(clim_in)
  # Fall back to the CPCRW climate dataset if the landscape lies outside the
  # standard regional domain (e.g. CPCRW is not covered by the Landscapes files)
  env_ext_clim_crs <- project(ext(env_rast), from = crs(env_rast), to = crs(ak_climate_var))
  if (all(is.na(values(crop(ak_climate_var[[1]], env_ext_clim_crs))))) {
    ak_climate_var <- rast(cpcrw_clim_in)
  }
  # Convert landscape raster to polygon (extent) and point geometries
  env_poly <- as.polygons(env_rast, extent = TRUE)
  env_points <- as.points(env_rast)
  # Buffer the landscape extent to ensure full coverage of bordering climate cells
  env_poly_buffer <- terra::buffer(env_poly, width = 4000)
  # Project buffer to the climate CRS to avoid reprojecting the full climate dataset
  pol_buffer_daymetcrs <- project(env_poly_buffer, ak_climate_var)
  # Crop and mask climate data to the buffered landscape area
  pol_buffer_daymetcrs_crop <- crop(ak_climate_var, pol_buffer_daymetcrs) |>
    mask(pol_buffer_daymetcrs)
  # Reproject cropped climate data back to the landscape CRS (equal-area Albers)
  var_buffer_albers <- project(pol_buffer_daymetcrs_crop, crs(env_rast))

  if (all(grepl("rsds", names(var_buffer_albers)))) {
    var_buffer_albers <- (var_buffer_albers * 86400) / 1000000
  }

  if (all(grepl("vp", names(var_buffer_albers)))) {
    vp_names <- paste0("vp_", seq_len(nlyr(var_buffer_albers)))
    if (!identical(names(var_buffer_albers), vp_names)) {
      names(var_buffer_albers) <- vp_names
    }
  }

  # Create the RU-to-climate-cell lookup: one row per RU, mapped to its climate cell
  climate_link <- terra::cells(var_buffer_albers, env_points) |>
    as.data.frame() |>
    rename(env.grid = "ID", climate.grid = "cell")

  write.table(climate_link, file.path(
    in_dir, "env.grid-climate.grid-link.txt"), row.names = FALSE)
  # Create data of climate.grid cell ID with values
  climate_extract <- as.data.frame(var_buffer_albers, cells = TRUE) |>
    dplyr::rename(climate.grid = "cell") |>
    right_join(climate_link, by = "climate.grid") |>
    distinct(climate.grid, .keep_all = TRUE) |>
    select(-env.grid)

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
      landscape = landscape_dir) |>
    dplyr::select(climate.grid, value, date, gcm, ssp, landscape) |>
    dplyr::rename(!!var := value)
    # names(df)[names(df) == "value"] <- var # for base R rename. no tidy evaluation. 
  write.table(ak_climate_var_df, file.path(out_dir, paste0(gcm, "-", ssp, "-", var, "-", year, ".txt")), row.names = FALSE, sep = "\t")
}


# --------- Parallel processing for multiple files -------- #
plan(multisession, workers = 24)

future_lapply(
  seq_len(nrow(param_grid)),
  function(i) {
    process_climate_link(
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




# ---------------------------------------------------------- #
# ------------------- TIMING TESTING ZONE ------------------ #
# ---------------------------------------------------------- #

start_process_climate_link <- Sys.time()
plan(multisession, workers = 18)

res <- future_lapply(
  seq_len(nrow(param_grid)),
  function(i) {
    process_climate_link(
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

gc(full = TRUE)
end_process_climate_link <- Sys.time()

end_process_climate_link - start_process_climate_link
# Time difference of 3.94498 mins
# -------------------------

start_process_climate <- Sys.time()

plan(multisession, workers = 18)

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
end_process_climate <- Sys.time()

end_process_climate - start_process_climate
# Time difference of 2.82361 mins