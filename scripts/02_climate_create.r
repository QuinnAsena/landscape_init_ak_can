library(terra)
library(sf)

ak_climate <- rast(
    "Z:/project_data/downscaling/Alaska/Downscaled CMIP6 NorESM2-MM/ssp126/tasmax/CMIP6 NorESM2-MM-ssp126-tasmax-2015.nc",
    lyrs = 4)
# plot(ak_climate)

env_files <- list.files(path = "C:/Users/asenaq/Documents/GitHub/landscape_init_ak_can", 
                        pattern = "grid.tif$", full.names = TRUE, recursive = TRUE)

env_grids_coarse <- lapply(env_files, \(ind) {
  r <- rast(ind)
  r <- aggregate(r, fact = 10)
})

env_grids_sp <- lapply(env_files, \(ind) {
  r <- rast(ind)
  r <- as.points(r, values = TRUE)
  names(r) <- "env.gridCell"
  r
})

ak_climate_proj <- lapply(env_grids_coarse, \(idx) {
  r <- project(ak_climate, idx, method = "near")
  values(r) <- seq_len(ncell(r))
  names(r) <- "climate.gridCell"
  r
})

ak_climate_sp <- lapply(ak_climate_proj, \(idx) {
  as.points(idx, values = TRUE)
})

rasValue <- Map(
  \(r, p) terra::extract(r, p, df = TRUE, bind = TRUE),
  ak_climate_proj, env_grids_sp
)

