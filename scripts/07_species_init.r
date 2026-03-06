library(terra)
library(purrr)
library(dplyr)
# This script converts Winslow's "forest_products_and_species" script and
# Uses Arielle's approach of masking with a seperate water product.
# Confirmed with Winslow that the water prodect is not identical to 
# the water layer in the ABoVE data, and should be more accurate.
dirs <- normalizePath(list.dirs(full.names = TRUE))
ak_landscape_dirs <- dirs[grepl(".*[\\\\/]landscape_[0-9]+$", dirs)]

landscape_ord <- as.integer(
  sub(".*landscape_([0-9]+).*$", "\\1", ak_landscape_dirs)
)
ord <- order(landscape_ord)
ak_landscape_dirs <- ak_landscape_dirs[ord]


process_species <- function(ak_landscape_dirs, above_lc_year = 1, water_decade_year = 3) {

  out_dir <- file.path(ak_landscape_dirs, "gis", "init")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  layers <- c(
    dem        = "dem_lcp10.tif",
    aspect     = "aspect_lcp10.tif",
    # hillshade  = "hillshade_lcp10.tif",
    env_grid   = "env.grid_disagg_10.tif",
    permafrost = "permafrost_lcp10.tif"
  )

  rasters <- lapply(file.path(ak_landscape_dirs, "gis", layers), \(ind) {
    if (basename(ind) == "env.grid_disagg_10.tif") {
      rast(ind, lyrs = above_lc_year)
    } else {
      rast(ind)
    }
  })
  names(rasters) <- names(layers)

  # Arielle uses the surface water dataset instead of the ABoVE dataset to
  # define water areas. Both look similar when plot but the surface water dataset
  # they found was more accurate and would not overlap forested area with water
  water_files <- list.files(file.path(ak_landscape_dirs, "ABoVE_Water"), full.names = TRUE)
  water_rast <- rast(water_files, lyrs = water_decade_year)
#   plot(rasters$dem)
#   env_grid_water <- ifel(rasters$env_grid == 15, 1, 0)
#   plot(env_grid_water)
  water_rast <- disagg(water_rast, fact = 3, method = "near")
  compareGeom(water_rast, rasters$env_grid, stopOnError = TRUE)
  water_rast <- ifel(water_rast == 1, 1, NA)
  dist <- distance(water_rast)
  water_mask <- ifel(dist <= 50, NA, 1)
  rasters <- lapply(rasters, mask, mask = water_mask)

  raster_df <- lapply(rasters, as.data.frame, xy = TRUE) |>
    purrr::reduce(dplyr::left_join, by = c("x", "y"))
  # NA in aspect is from the raster border, aspect is calculated in 05_dem_process.r
  # from the DEM. Border cells become NA
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

  # This is very slightly different to Winslow's code in that NA values in aspect
  # will default to the value in the Above category rather than remaining NA.
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
        Above %in% 5:9                                      ~ "Potential-forest",
        TRUE                                                ~ NA_character_,
      ),
      forest_species_init = case_when(
        species == "Black.spruce" ~ 1, 
        species == "White.spruce" ~ 2,
        species == "Aspen"       ~ 3,
        species == "Birch"        ~ 4,
        species == "Mixed"        ~ 5,
        species == "Potential-forest" ~ 6,
        TRUE ~ 7
      ),
    ) |>
    filter(forest.type != "Non-forest")

  raster_df_small <- raster_df |>
    select(x, y, forest_species_init)

  forest.species <- rast(raster_df_small, type = "xyz", crs = crs(rasters[[1]]))
  writeRaster(forest.species, filename = file.path(out_dir, paste0("forest_species_init_lc_yr", above_lc_year, ".tif")), overwrite = TRUE)
}


#--------------- Run the function ---------------#

dirs <- normalizePath(list.dirs(full.names = TRUE))
ak_landscape_dirs <- dirs[grepl(".*[\\\\/]landscape_[0-9]+$", dirs)]

landscape_ord <- as.integer(
  sub(".*landscape_([0-9]+).*$", "\\1", ak_landscape_dirs)
)
ord <- order(landscape_ord)
ak_landscape_dirs <- ak_landscape_dirs[ord]

lapply(ak_landscape_dirs, process_species, above_lc_year = 31, water_decade_year = 3)
lapply(ak_landscape_dirs, process_species, above_lc_year = 1, water_decade_year = )
