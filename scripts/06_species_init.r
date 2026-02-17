library(terra)
library(purrr)
library(dplyr)

#ak_landscape_dirs <- ak_landscape_dirs[2]

process_species <- function(ak_landscape_dirs) {

  out_dir <- file.path(ak_landscape_dirs, "gis", "init")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  layers <- c(
    dem        = "dem_lcp10.tif",
    aspect     = "aspect_lcp10.tif",
    hillshade  = "hillshade_lcp10.tif",
    env_grid   = "env.grid_disagg_10.tif",
    permafrost = "permafrost_lcp10.tif"
  )

  rasters <- lapply(file.path(ak_landscape_dirs, "gis", layers), rast)
  names(rasters) <- names(layers)

  raster_df <- lapply(rasters, as.data.frame, xy = TRUE) |>
    purrr::reduce(dplyr::left_join, by = c("x", "y"))
  # NA in aspect is from the raster border, aspect is calculated in 05_dem_process.r
  # from the DEM. Border cells become NA
  raster_df <- raster_df |>
    rename(Above = ABoVE_LandCover_Bh03v02_31,
           elevation = ends_with("v4.1_dem"),
           hillshade = ends_with("v4.1_browse"),
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
  # will default to the value in the Above category rather than to NA.
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
      species2 = case_when(
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
    select(x, y, species2)

  forest.species <- rast(raster_df_small, type = "xyz", crs = crs(rasters[[1]]))
  writeRaster(forest.species, filename = file.path(out_dir, "forest_species_init.tif"), overwrite = TRUE)
}

dirs <- normalizePath(list.dirs(full.names = TRUE))
ak_landscape_dirs <- dirs[grepl(".*[\\\\/]landscape_[0-9]+$", dirs)]

landscape_ord <- as.integer(
  sub(".*landscape_([0-9]+).*$", "\\1", ak_landscape_dirs)
)
ord <- order(landscape_ord)
ak_landscape_dirs <- ak_landscape_dirs[ord]

lapply(ak_landscape_dirs, process_species)
