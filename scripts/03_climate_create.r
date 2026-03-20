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

above_study_domain_file <- list.files(
  "//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/ABoVE_reference_grid_v2_1527/data",
  pattern = "\\.tif$", full.names = TRUE)

above_study_domain <- rast(above_study_domain_file)
plot(above_study_domain)
crs(above_study_domain)

# This script converts Winslow's "climate_processing_step1.Rmd"
# Load one layer of the whole of Alaska as a template to crop landcapes
ak_climate <- rast(
  "//10.60.2.10/FF_Lab/project_data/downscaling/Alaska/Downscaled CMIP6 NorESM2-MM/ssp126/tasmax/CMIP6 NorESM2-MM-ssp126-tasmax-2015.nc",
  lyrs = 4)
# plot(ak_climate)
# Load env.grid files (careful of crs here, they are in ESRI:102001)

ak_climate_to_above <- project(ak_climate, crs(above_study_domain))
writeRaster(ak_climate_to_above, file.path(here("data"), "ak_climate_to_above.tif"),
            overwrite = TRUE)


env_files <- list.files(path = file.path(landscape_dirs, "gis"),
                        pattern = "env.grid.tif$", full.names = TRUE, recursive = TRUE)



# Aggregate the env.grid to match 1000x1000 of climtae data
env_grids_coarse <- lapply(env_files, \(ind) {
  r <- rast(ind)
  r_agg <- aggregate(r, fact = 10)
})
names(env_grids_coarse) <- landscape_names



# Convert env.grid to points for extraction
env_grids_sp <- Map(\(env_files, nm) {
  out <- file.path(nm, "supporting_data", "climate")
  dir.create(out, recursive = TRUE)
  r <- rast(env_files)
  r <- as.points(r, values = TRUE, na.rm = TRUE)
  # shape files have a 10 chr limit in field names. renamed from env.gridCell
  names(r) <- "env.grid"
  writeVector(r, file.path(out, "env_cells_extract.shp"),
              overwrite = TRUE)
  r
}, env_files, landscape_names)
names(env_grids_sp) <- landscape_names


# reproject climate to env.grid (matches resolution and extent)
ak_climate_proj <- Map(\(tmpl, nm) {
  out <- file.path(nm, "supporting_data", "climate")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)


  # tmpl <- rast(env_files[1])
  # which(values(tmpl) == 1)
  # plot(tmpl)
  # plot(ifel(is.na(tmpl), 1, NA))

  # r <- project(ak_climate, crs(tmpl))
  # plot(r)
  # sum(is.na(values(r)))
  # r <- mask(r, tmpl)
  # plot(r)

  # r_agg <- aggregate(r, fact = 10)
  # plot(r_agg)
  # r_agg_msk <- mask(r_agg, tmpl)
  # plot(r_agg_msk)

  # non_na_idx <- which(!is.na(values(r)))
  # values(r) <- NA
  # values(r)[non_na_idx] <- seq_along(non_na_idx)
  # units(r) <- NA
  # plot(r)


  r <- project(ak_climate_to_above, tmpl, method = "near")
  plot(r)
  sum(is.na(values(r)))

  non_na_idx <- which(!is.na(values(tmpl)))
  values(r) <- NA
  values(r)[non_na_idx] <- seq_along(non_na_idx)
  units(r) <- NA
  plot(r)

  # values(r) <- seq_len(ncell(r))
  # renamed "climate.gridCell" to climate.grid.
  names(r)  <- "climate.grid"
  writeRaster(r, file.path(out, "climate.grid.tif"),
              overwrite = TRUE) # datatype = "INT4S"?
  r
}, env_grids_coarse, names(env_grids_coarse))

plot(ak_climate_proj[[1]])
sum(is.na(values(ak_climate_proj[[1]])))





# convert projected climate to points for later
ak_climate_sp <- Map(\(idx, nm) {
  out <- file.path(nm, "supporting_data", "climate")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  clim_vec <- as.points(idx, values = TRUE, na.rm = TRUE)
  writeVector(clim_vec, file.path(out, "climate_cells_extract.shp"),
              overwrite = TRUE)
  clim_vec
}, ak_climate_proj, names(ak_climate_proj))

# Extract values from projected climate at env.grid points
# env.grid RUs now align with climate gridcells
rasValue <- Map(\(r, p, nm) {
  out <- file.path(nm, "supporting_data", "climate")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  env_clim_link <- terra::extract(r, p, df = TRUE, bind = TRUE)
  write.table(env_clim_link, file.path(out, "env.grid-climate.grid-link.txt"),
              row.names = FALSE)
  env_clim_link
}, ak_climate_proj, env_grids_sp, names(ak_climate_proj))


plot(ifel(is.na(ak_climate_proj[[1]]), 1, NA))
points(env_grids_sp[[1]][is.na(rasValue[[1]]$climate.grid)])


table(is.na(values(ak_climate_proj[[1]])))
table(is.na(rasValue[[1]]$climate.grid))
table(rasValue[[1]]$climate.grid)
compareGeom(env_grids_coarse[[1]], ak_climate_proj[[1]], stopOnError = FALSE)

x <- as.data.frame(rasValue[[1]])
x[which(x$env.grid == 1), ]
x[which(x$climate.grid == 1), ]


process_climate <- function(gcm, ssp, var, year, landscape_dir) {

  in_dir <- file.path(landscape_dir, "supporting_data", "climate")
  out_dir <- file.path(in_dir, gcm, ssp, var)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  ak_clim_in <- file.path("//10.60.2.10/FF_Lab/project_data/downscaling/Alaska", paste0("Downscaled CMIP6 ", gcm), ssp, var, paste0("CMIP6 ", gcm, "-", ssp, "-", var, "-", year, ".nc"))

  ak_climate_sp_files <- list.files(
    in_dir, full.names = TRUE, pattern = "\\climate_cells_extract.shp$"
  )

  ak_climate_tif_files <- list.files(
    in_dir, full.names = TRUE, pattern = "\\.tif$"
  )

  ak_climate_var <- rast(ak_clim_in)
  ak_climate_sp <- vect(ak_climate_sp_files)
  names(ak_climate_sp) <- "climate.grid"
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
