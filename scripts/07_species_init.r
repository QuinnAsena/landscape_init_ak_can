library(terra)
library(purrr)
library(dplyr)
library(here)
library(future.apply)
# Assigns initial forest species to each RU cell based on ABoVE land cover class,
# aspect direction, and permafrost presence. Outputs a raster of integer species
# codes used in step 09 to build the stand grid and in step 10 for the env file.
# Uses Arielle's approach of masking with the ABoVE surface water product rather
# than the land cover water class — confirmed with Winslow to be more accurate
# and avoids overlap between forested and water-covered cells.
# Based on Winslow's "forest_products_and_species" script.

# ABoVE landcover is 1984-2014, above_lc_year layer = select year
# ABoVE surface water is decadal 1991-2011, water_decade_year layer = select decade


process_species <- function(landscape_name,
                            above_lc_year = 1,
                            water_decade_year = 1) {

  cat("\n\nprocessing: ", landscape_name, "\n\n")

  out_dir <- here(landscape_name, "supporting_data", "gis", "init")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  layers <- c(
    dem        = "dem_lcp10.tif",
    aspect     = "aspect_lcp10.tif",
    # hillshade  = "hillshade_lcp10.tif",
    env_grid   = "env.grid_disagg_10.tif",
    permafrost = "permafrost_lcp10.tif"
  )
  rasters <- lapply(
    here(landscape_name, "supporting_data", "gis", layers),
    \(ind) {
      if (basename(ind) == "env.grid_disagg_10.tif") {
        rast(ind, lyrs = above_lc_year)
      } else {
        rast(ind)
      }
    })
  names(rasters) <- names(layers)
  # Arielle uses the surface water dataset instead of the ABoVE dataset to
  # define water areas. Both look similar when plotted but the surface water
  # dataset was more accurate and would not overlap forested area with water.
  water_files <- list.files(
    here(landscape_name, "supporting_data", "ABoVE_Water"),
    full.names = TRUE)
  water_rast <- rast(water_files, lyrs = water_decade_year)
  water_rast <- disagg(water_rast, fact = 3, method = "near")
  compareGeom(water_rast, rasters$env_grid, stopOnError = TRUE)
  water_rast <- ifel(water_rast == 1, 1, NA)
  dist <- distance(water_rast)
  water_mask <- ifel(dist <= 50, NA, 1)
  rasters <- lapply(rasters, mask, mask = water_mask)

  raster_df <- lapply(rasters, as.data.frame, xy = TRUE) |>
    purrr::reduce(dplyr::left_join, by = c("x", "y"))
  # Aspect border NAs arise because terrain() requires neighbours on all sides —
  # edge cells of the DEM have no outer neighbour. These are handled in the
  # species rules below by falling through to the Above-class-only conditions.
  raster_df <- raster_df |>
    rename(Above = starts_with("ABoVE_LandCover"),
           elevation = ends_with("v4.1_dem"),
           # hillshade = ends_with("v4.1_browse"),
           permafrost = permafrost_repr) |>
    mutate(
      aspect.dir = case_when(
        aspect == -1                     ~ "flat",
        aspect > -1  & aspect <= 45      ~ "N",
        aspect > 45  & aspect <= 135     ~ "E",
        aspect > 135 & aspect <= 225     ~ "S",
        aspect > 225 & aspect <= 315     ~ "W",
        aspect > 315                     ~ "N",
        TRUE                             ~ NA_character_
      ),
      forest.type = case_when(
        Above == 1                       ~ "Evergreen",
        Above == 2                       ~ "Deciduous",
        Above == 3                       ~ "Mixed",
        Above == 4                       ~ "Woodland",
        Above %in% 5:9                   ~ "Potential-forest",
        TRUE                             ~ "Non-forest"
      ),
      permafrost = coalesce(permafrost, 0)
    )

  # Species rules follow Winslow's original logic with one difference: cells
  # with NA aspect fall through to the class-only conditions (e.g. Above == 1
  # assigns White.spruce) rather than remaining unclassified as in the original.
  raster_df <- raster_df |>
    mutate(
      species = case_when(
        Above == 1 & aspect.dir == "flat" & permafrost == 1 ~ "Black.spruce",
        Above == 1 & aspect.dir == "flat" & permafrost == 0 ~ "White.spruce",
        Above == 1 & aspect.dir == "N"                      ~ "Black.spruce",
        Above == 1                                          ~ "White.spruce",
        Above == 4                                          ~ "Black.spruce",
        Above == 2 & aspect.dir == "S"                      ~ "Aspen",
        Above == 2                                          ~ "Birch",
        Above == 3                                          ~ "Mixed",
        Above %in% 5:9                                     ~ "Potential-forest",
        TRUE                                               ~ NA_character_,
      ),
      forest_species_init = case_when(
        species == "Black.spruce"     ~ 1,
        species == "White.spruce"     ~ 2,
        species == "Aspen"            ~ 3,
        species == "Birch"            ~ 4,
        species == "Mixed"            ~ 5,
        species == "Potential-forest" ~ 6,
        TRUE                          ~ 7
      ),
    ) |>
    filter(forest.type != "Non-forest")

  raster_df_small <- raster_df |>
    select(x, y, forest_species_init)

  forest_species <- rast(raster_df_small, type = "xyz", crs = crs(rasters[[1]]))
  writeRaster(forest_species,
              filename = file.path(
                out_dir,
                paste0("forest_species_init_lc_yr", above_lc_year, ".tif")),
              overwrite = TRUE)
}


#--------------- Run the function ---------------#

dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])

plan(multisession, workers = 2)
future_lapply(landscape_names, process_species,
              above_lc_year = 1, water_decade_year = 1,
              future.seed = TRUE)
plan(sequential)

plan(multisession, workers = 2)
future_lapply(landscape_names, process_species,
              above_lc_year = 31, water_decade_year = 3,
              future.seed = TRUE)
plan(sequential)
