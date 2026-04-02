library(terra)
library(dplyr)
library(tidyr)
library(here)
library(future.apply)
# Builds the iLand environment file for each landscape by combining:
# the RU grid (step 02), species initialisation (step 07), and soil rasters.
# Calculates soil carbon, nitrogen, and moss biomass pools by forest type.
# Two versions: build_env_file uses the interpolated climate grid (step 03
# process_climate); build_env_file_link uses the linked climate grid
# (step 03 process_climate_link) and reads the RU-to-climate-cell lookup.
# Based on Winslow's "generating environment file.Rmd".

build_env_file <- function(landscape_name, soil_rast) {

  message("Processing: ", landscape_name)

  env_files <- list.files(
    path = here(landscape_name),
    pattern = "env.grid.tif$", full.names = TRUE, recursive = TRUE)

  sp_init_files <- list.files(
    path = here(landscape_name),
    pattern = "forest_species_init_lc_yr1.tif$", full.names = TRUE, recursive = TRUE)

  env.grid <- rast(env_files)
  env.grid.sp <- as.points(env.grid, values = TRUE)
  sp_init <- rast(sp_init_files)

  out_dir <- here(landscape_name, "gis")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  env.grid.df <- as.data.frame(env.grid) |>
    rename(env.grid = ru) |>
    mutate(add = landscape_name) |>
    tidyr::unite("model.climate.tableName", c(add, env.grid), remove = FALSE) |>
    select(env.grid, model.climate.tableName)

  species.table <- terra::extract(sp_init, env.grid.sp, df = TRUE)

  soil_rast_proj <- lapply(soil_rast, project, y = env.grid, method = "bilinear")
  soil_tables <- lapply(soil_rast_proj, terra::extract, y = env.grid.sp, df = TRUE)

  total <- purrr::reduce(c(soil_tables, list(species.table)), left_join, by = "ID")

  total <- total |>
    mutate(
      across(ends_with("mean"), ~ replace_na(.x, 0)), # soil NAs outside coverage → 0
      model.site.youngLabileC = case_when(
        forest_species_init %in% c(1, 2) ~ runif(n(), 48682, 96901),
        forest_species_init %in% c(3, 4) ~ runif(n(), 17371, 31765),
        forest_species_init == 5       ~ runif(n(), 33026.5, 64336),
        TRUE                           ~ runif(n(), 48682, 96901)
      ),
      model.site.youngLabileN = case_when(
        forest_species_init %in% c(1, 2) ~ model.site.youngLabileC / 32.62,
        forest_species_init %in% c(3, 4) ~ model.site.youngLabileC / 23.58,
        forest_species_init == 5       ~ model.site.youngLabileC / 28.01,
        TRUE                           ~ model.site.youngLabileC / 32.62
      ),
      model.site.youngRefractoryC = case_when(
        forest_species_init %in% c(1, 2) ~ 17000,
        forest_species_init %in% c(3, 4) ~ 20020,
        forest_species_init == 5       ~ 18500,
        TRUE                           ~ 17000
      ),
      model.site.youngRefractoryN = case_when(
        forest_species_init %in% c(1, 2) ~ model.site.youngRefractoryC / 425,
        forest_species_init %in% c(3, 4) ~ model.site.youngRefractoryC / 417.1,
        forest_species_init == 5       ~ model.site.youngRefractoryC / 421.05,
        TRUE                           ~ model.site.youngRefractoryC / 425
      ),
      model.site.somC = 35000,
      model.site.somN = model.site.somC / 20,
      model.settings.permafrost.moss.biomass = case_when(
        forest_species_init == 1 ~ runif(n(), 1.55, 2.79),
        forest_species_init == 2 ~ runif(n(), 0.31, 0.93),
        forest_species_init %in% c(3, 4) ~ runif(n(), 0, 0.0001),
        forest_species_init == 5 ~ runif(n(), 0.62, 1.55),
        TRUE                     ~ runif(n(), 1.55, 2.79)
      )
    )

  total_join <- total |>
    rename(env.grid = ID) |>
    left_join(env.grid.df, by = "env.grid") |>
    mutate(across(everything(), ~ tidyr::replace_na(.x, 0)))

  env.file <- total_join |>
    mutate(
      across(
        c(depth_mean, sand_mean, silt_mean, clay_mean,
          model.site.youngLabileC, model.site.youngLabileN,
          model.site.youngRefractoryC, model.site.youngRefractoryN,
          model.site.somC, model.site.somN), ~ round(.x, 0)),
      model.settings.permafrost.moss.biomass = round(
        model.settings.permafrost.moss.biomass, 4),
      model.site.availableNitrogen = 45) |>
    select(
      env.grid,
      model.climate.tableName,
      model.site.availableNitrogen,
      model.site.soilDepth     = depth_mean,
      model.site.pctSand       = sand_mean,
      model.site.pctSilt       = silt_mean,
      model.site.pctClay       = clay_mean,
      model.site.youngLabileC,
      model.site.youngLabileN,
      model.site.youngRefractoryC,
      model.site.youngRefractoryN,
      model.site.somC,
      model.site.somN,
      model.settings.permafrost.moss.biomass
    )

  write.table(env.file,
              file.path(out_dir, "env.file.txt"),
              row.names = FALSE, sep = "\t")
}


dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])

# Soil rasters (depth, sand, silt, clay) pre-processed to AK extent.
# Layer names are standardised to the "_mean" suffix used in the mutate block.
soil_files <- list.files(
  "//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/soils/ak",
  full.names = TRUE)
soil_names <- sub("_ak\\.tif$", "", basename(soil_files))
soil_rast <- lapply(soil_files, terra::rast)
names(soil_rast) <- soil_names

soil_rast <- Map(\(r, nm) {
  nnm <- paste0(nm, "_mean")
  names(r) <- nnm
  r
}, soil_rast, soil_names)

set.seed(1984)
plan(multisession)
future_lapply(landscape_names, build_env_file, soil_rast = soil_rast,
              future.seed = TRUE)
plan(sequential)


# --------------------------------------------------------- #
# --------------  Process env file with link  ------------- #
# --------------------------------------------------------- #

build_env_file_link <- function(landscape_name, soil_rast) {

  message("Processing: ", landscape_name)

  env_files <- list.files(
    path = here(landscape_name),
    pattern = "env.grid.tif$", full.names = TRUE, recursive = TRUE)

  climate_link_files <- list.files(
    path = here(landscape_name, "supporting_data", "climate_link"),
    pattern = "env.grid-climate.grid-link.txt$", full.names = TRUE,
    recursive = TRUE)

  sp_init_files <- list.files(
    path = here(landscape_name, "supporting_data"),
    pattern = "forest_species_init_lc_yr1.tif$", full.names = TRUE,
    recursive = TRUE)

  env.grid <- rast(env_files)
  env.grid.sp <- as.points(env.grid, values = TRUE)
  sp_init <- rast(sp_init_files)
  climate.link <- read.table(climate_link_files, header = TRUE)

  out_dir <- here(landscape_name, "gis")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  env.grid.df <- climate.link |>
    mutate(add = landscape_name) |>
    tidyr::unite("model.climate.tableName", c(add, climate.grid), remove = FALSE) |>
    select(env.grid, model.climate.tableName)

  species.table <- terra::extract(sp_init, env.grid.sp, df = TRUE)

  soil_rast_proj <- lapply(soil_rast, project, y = env.grid, method = "bilinear")
  soil_tables <- lapply(soil_rast_proj, terra::extract, y = env.grid.sp, df = TRUE)

  total <- purrr::reduce(c(soil_tables, list(species.table)), left_join, by = "ID")

  total <- total |>
    mutate(
      across(ends_with("mean"), ~ replace_na(.x, 0)), # soil NAs outside coverage → 0
      model.site.youngLabileC = case_when(
        forest_species_init %in% c(1, 2) ~ runif(n(), 48682, 96901),
        forest_species_init %in% c(3, 4) ~ runif(n(), 17371, 31765),
        forest_species_init == 5       ~ runif(n(), 33026.5, 64336),
        TRUE                           ~ runif(n(), 48682, 96901)
      ),
      model.site.youngLabileN = case_when(
        forest_species_init %in% c(1, 2) ~ model.site.youngLabileC / 32.62,
        forest_species_init %in% c(3, 4) ~ model.site.youngLabileC / 23.58,
        forest_species_init == 5       ~ model.site.youngLabileC / 28.01,
        TRUE                           ~ model.site.youngLabileC / 32.62
      ),
      model.site.youngRefractoryC = case_when(
        forest_species_init %in% c(1, 2) ~ 17000,
        forest_species_init %in% c(3, 4) ~ 20020,
        forest_species_init == 5       ~ 18500,
        TRUE                           ~ 17000
      ),
      model.site.youngRefractoryN = case_when(
        forest_species_init %in% c(1, 2) ~ model.site.youngRefractoryC / 425,
        forest_species_init %in% c(3, 4) ~ model.site.youngRefractoryC / 417.1,
        forest_species_init == 5       ~ model.site.youngRefractoryC / 421.05,
        TRUE                           ~ model.site.youngRefractoryC / 425
      ),
      model.site.somC = 35000,
      model.site.somN = model.site.somC / 20,
      model.settings.permafrost.moss.biomass = case_when(
        forest_species_init == 1 ~ runif(n(), 1.55, 2.79),
        forest_species_init == 2 ~ runif(n(), 0.31, 0.93),
        forest_species_init %in% c(3, 4) ~ runif(n(), 0, 0.0001),
        forest_species_init == 5 ~ runif(n(), 0.62, 1.55),
        TRUE                     ~ runif(n(), 1.55, 2.79)
      )
    )

  total_join <- total |>
    rename(env.grid = ID) |>
    left_join(env.grid.df, by = "env.grid") |>
    mutate(across(everything(), ~ tidyr::replace_na(.x, 0)))

  env.file <- total_join |>
    mutate(
      across(
        c(depth_mean, sand_mean, silt_mean, clay_mean,
          model.site.youngLabileC, model.site.youngLabileN,
          model.site.youngRefractoryC, model.site.youngRefractoryN,
          model.site.somC, model.site.somN), ~ round(.x, 0)),
      model.settings.permafrost.moss.biomass = round(
        model.settings.permafrost.moss.biomass, 4),
      model.site.availableNitrogen = 45) |>
    select(
      env.grid,
      model.climate.tableName,
      model.site.availableNitrogen,
      model.site.soilDepth     = depth_mean,
      model.site.pctSand       = sand_mean,
      model.site.pctSilt       = silt_mean,
      model.site.pctClay       = clay_mean,
      model.site.youngLabileC,
      model.site.youngLabileN,
      model.site.youngRefractoryC,
      model.site.youngRefractoryN,
      model.site.somC,
      model.site.somN,
      model.settings.permafrost.moss.biomass
    )

  write.table(env.file,
              file.path(out_dir, "env.file_link.txt"),
              row.names = FALSE, sep = "\t")
}

set.seed(1984)
plan(multisession)
future_lapply(landscape_names, build_env_file_link, soil_rast = soil_rast,
              future.seed = TRUE)
plan(sequential)
