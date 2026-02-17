library(terra)
library(sf)
library(tidyr)
library(dplyr)
library(lubridate)
library(future.apply)

# Load one layer of the whole of Alaska as a template to crop landcapes
ak_climate <- rast(
  "Z:/project_data/downscaling/Alaska/Downscaled CMIP6 NorESM2-MM/ssp126/tasmax/CMIP6 NorESM2-MM-ssp126-tasmax-2015.nc",
  lyrs = 4)
# plot(ak_climate)

# Load env.grid files (careful of crs here, they are in ESRI:102001)
env_files <- list.files(path = "C:/Users/asenaq/Documents/GitHub/landscape_init_ak_can", 
                        pattern = "env.grid.tif$", full.names = TRUE, recursive = TRUE)

landscape_ord <- as.integer(
  sub(".*landscape_([0-9]+).*$", "\\1", env_files)
)
ord <- order(landscape_ord)
env_files <- env_files[ord]

landscape_names <- sub(".*(landscape_[0-9]+).*", "\\1", env_files)

# Aggregate the env.grid to match 1000x1000 of climtae data
env_grids_coarse <- lapply(env_files, \(ind) {
  rast(ind) |> aggregate(fact = 10)
})
names(env_grids_coarse) <- landscape_names

# Convert env.grid to points for extraction
env_grids_sp <- Map(\(env_files, nm) {
  out <- file.path(nm, "climate")
  r <- rast(env_files)
  r <- as.points(r, values = TRUE)
  names(r) <- "env.gridCell"
  writeVector(r, file.path(out, "env_cells_extract.shp"),
              overwrite = TRUE)
  r
}, env_files, landscape_names)
names(env_grids_sp) <- landscape_names

# reproject climate to env.grid (matches resolution and extent)
ak_climate_proj <- Map(\(tmpl, nm) {
  out <- file.path(nm, "climate")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  r <- project(ak_climate, tmpl, method = "near")
  values(r) <- seq_len(ncell(r))
  names(r)  <- "climate.gridCell"
  writeRaster(r, file.path(out, "climate.grid.tif"),
              overwrite = TRUE) # datatype = "INT4S"?
  r
}, env_grids_coarse, names(env_grids_coarse))


# convert projected climate to points for later
ak_climate_sp <- Map(\(idx, nm) {
  out <- file.path(nm, "climate")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  clim_vec <- as.points(idx, values = TRUE)
  writeVector(clim_vec, file.path(out, "climate_cells_extract.shp"),
              overwrite = TRUE)
  clim_vec
}, ak_climate_proj, names(ak_climate_proj))

# Extract values from projected climate at env.grid points
# env.grid RUs now align with climate gridcells
rasValue <- Map(\(r, p, nm) {
  out <- file.path(nm, "climate")
  env_clim_link <- terra::extract(r, p, df = TRUE, bind = TRUE)
  write.table(env_clim_link, file.path(out, "env.grid to climate.grid link.txt"),
              row.names = FALSE)
  env_clim_link
}, ak_climate_proj, env_grids_sp, names(ak_climate_proj))

lapply(rasValue, head, 20)
lapply(rasValue, tail, 20)

# Different NorESM timespan? 1980 vs 1950?

process_climate <- function(gcm, ssp, var, year, ak_climate_dirs) {
  out_dir <- file.path(ak_climate_dirs, gcm, ssp, var)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  ak_clim_in <- file.path("Z:/project_data/downscaling/Alaska", paste0("Downscaled CMIP6 ", gcm), ssp, var, paste0("CMIP6 ", gcm, "-", ssp, "-", var, "-", year, ".nc"))

  ak_climate_sp_files <- list.files(
    ak_climate_dirs, full.names = TRUE, pattern = "\\.shp$"
  )

  ak_climate_tif_files <- list.files(
    ak_climate_dirs, full.names = TRUE, pattern = "\\.tif$"
  )

  landscape_id <- sub(
    ".*[\\\\/]landscape_([0-9]+)[\\\\/].*",
    "landscape\\1",
    ak_climate_sp_files
  )

  ak_climate_var <- rast(ak_clim_in)
  ak_climate_sp <- vect(ak_climate_sp_files)
  ak_climate_proj <- rast(ak_climate_tif_files)

  ak_climate_var_proj <- project(ak_climate_var, ak_climate_proj, method="bilinear")
  rm(ak_climate_var); gc()

  if (all(grepl("rsds", names(ak_climate_var_proj)))) {
    ak_climate_var_proj <- (ak_climate_var_proj * 86400) / 1000000
  }

  if (all(grepl("vp", names(ak_climate_var_proj)))) {
    vp_names <- paste0("vp_", seq_len(nlyr(ak_climate_var_proj)))
    if (!identical(names(ak_climate_var_proj), vp_names)) {
      names(ak_climate_var_proj) <- vp_names
    }
  }

  ak_climate_var_df <- as.data.frame(terra::extract(ak_climate_var_proj, ak_climate_sp, bind = TRUE))
  names(ak_climate_var_df)[1] <- "climate.gridCell" # shape files have a 10 chr limit in field names. maybe gpkg is a workaround?

  ak_climate_var_df <- ak_climate_var_df |>
    tidyr::pivot_longer(
      cols = -climate.gridCell,
      names_to = "y_day",
      values_to = "value") |>
    dplyr::mutate(
      y_day = as.numeric(sub(paste0(var, "_"), "", y_day)),
      day_of_year = ifelse(lubridate::leap_year(year) & y_day >= 60, y_day + 1, y_day),
      date = lubridate::make_date(year) + lubridate::days(day_of_year - 1),
      value = round(value, 3),
      gcm = gcm,
      ssp = ssp,
      landscape = landscape_id) |>
    dplyr::select(climate.gridCell, value, date, gcm, ssp, landscape) |>
    dplyr::rename(!!var := value)
    # names(df)[names(df) == "value"] <- var # for base R rename. no tidy evaluation. 
  write.table(ak_climate_var_df, file.path(out_dir, paste0(gcm, "-", ssp, "-", var, "-", year, ".txt")), row.names = FALSE, sep = "\t")
}


# --------- Parallel processing for multiple files --------
gcm <- "NorEsm2-MM"
ssp <- "ssp126"
var <- c("tasmax", "hurs", "pr", "rsds", "tasmin", "vp")
year <- 2015:2016

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
param_grid <- base::merge(
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
