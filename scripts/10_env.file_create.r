library(terra)
library(dplyr)
library(tidyr)
library(here)
# This script converts Winslow's "generating envieonmtnt file.Rmd"
# Read all the outputs from step 02 and 03

build_env_file <- function(landscape_dir, soil_rast) {

  message("Processing: ", basename(landscape_dir))

  env_files <- list.files(
    path = landscape_dir,
    pattern = "env.grid.tif$", full.names = TRUE, recursive = TRUE)

  env_sp_files <- list.files(
    path = landscape_dir,
    pattern = "env_cells_extract.shp$", full.names = TRUE, recursive = TRUE)

  climate_link_files <- list.files(
    path = landscape_dir,
    pattern = "env.grid-climate.grid-link.txt$", full.names = TRUE, recursive = TRUE)

  sp_init_files <- list.files(
    path = landscape_dir,
    pattern = "forest_species_init_lc_yr1.tif$", full.names = TRUE, recursive = TRUE)

  landscape_names <- basename(landscape_dir)

  env.grid <- rast(env_files)
  env.grid.sp <- vect(env_sp_files)
  sp_init <- rast(sp_init_files)
  climate.link <- read.table(climate_link_files, header = TRUE)

  out_dir <- file.path(landscape_dir, "gis")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # combine the climate link to the env.grid
  # env.grid.sp_join <- terra::merge(env.grid.sp, climate.link, by = "env.grid", all.x = TRUE)
  # env.grid.df <- as.data.frame(env.grid.sp_join) |>
  #   mutate(add = landscape_names) |>
  #   tidyr::unite("model.climate.tableName", c(add, climate.grid), remove = T)


  env.grid.df <- as.data.frame(env.grid.sp) |>
    mutate(add = landscape_names) |>
    tidyr::unite("model.climate.tableName", c(add, env.grid), remove = FALSE) |>
    select(env.grid, model.climate.tableName)


  species.table <- terra::extract(sp_init, env.grid.sp, df = TRUE)
  
  plot(ifel(is.na(sp_init), 1, NA), col = "black")
  sum(is.na(values(sp_init)))
  sum(values(sp_init), na.rm = TRUE)
  ncell(sp_init)

  sum(is.na(species.table$forest_species_init))
  dim(species.table)

  soil_rast_proj <- lapply(soil_rast, project, y = env.grid, method = "bilinear")
  soil_tables <- lapply(soil_rast_proj, terra::extract, y = env.grid.sp, df = TRUE)
  lapply(soil_tables, head)

  x <- lapply(soil_rast_proj, \(r) {
    ifel(is.na(r), 1, NA)
  }) |> rast()
  plot(x)

  total <- purrr::reduce(c(soil_tables, list(species.table)), left_join, by = "ID")
  head(total)

  colSums(is.na(total))

  total <- total |>
    mutate(
      across(ends_with("mean"), ~ replace_na(.x, 0)),
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
      model.settings.permafrost.moss.biomass = round(model.settings.permafrost.moss.biomass, 4),
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
  
  write.table(env.file, file.path(out_dir, "env.file.txt"), row.names = FALSE, sep = "\t")
}


dirs <- list.dirs(here(), recursive = FALSE)
landscape_dirs <- dirs[grepl("landscape_", basename(dirs))]

# Read all the soils data (all ak). This has already been processed at some point
soil_files <- list.files("//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/soils/ak", full.names = TRUE)
soil_names <- sub("_ak\\.tif$", "", basename(soil_files))
soil_rast <- lapply(soil_files, terra::rast)
names(soil_rast) <- soil_names

soil_rast <- Map(\(r, nm) {
  nnm <- paste0(nm, "_mean")
  names(r) <- nnm
  r
}, soil_rast, soil_names)


set.seed(1984)
lapply(landscape_dirs, build_env_file, soil_rast = soil_rast)
