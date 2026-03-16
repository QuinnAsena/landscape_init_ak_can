#---------- Create stand grid rasters for each landscape ----------#

# Read in the species init generated in step 6 where the Above data were
# converted to forest_types of the modelled species.
library(terra)
library(here)

process_stand_grid <- function(ak_landscape_dir, year_lyr, sapinit_dict) {
  in_dir <- here(ak_landscape_dir, "supporting_data", "gis", "init")
  output_dir <- file.path(ak_landscape_dir, "gis")
  dir.create(output_dir)

  forest_type_rast <- terra::rast(
    file.path(in_dir, paste0("forest_species_init_lc_yr", year_lyr, ".tif"))
  )

  # Class 6 becomes "potential forest" using a value not in the stand ranges
  forest_type_rast <- terra::ifel(
    forest_type_rast == 6, max(sapinit_dict$max_stand_id) + 1,
    forest_type_rast
  )

  # For each forest type, assign random stand IDs
  vals <- terra::values(forest_type_rast)
  # Now use the dictionary matching id to forest class to scatter the landscape
  # with random stands from the correct class
  for (i in seq_len(nrow(sapinit_dict))) {
    idx <- which(vals == sapinit_dict$forest_class[i])
      vals[idx] <- sample(
        sapinit_dict$min_stand_id[i]:sapinit_dict$max_stand_id[i],
        size = length(idx), replace = TRUE)
  }
  terra::values(forest_type_rast) <- vals

  # NA becomes no-data -9999. iLand documentation says -1 for this but -9999 works I guess
  forest_type_rast <- terra::ifel(
    is.na(forest_type_rast), -9999, forest_type_rast)

  terra::writeRaster(
    forest_type_rast,
    file.path(output_dir, "stand_grid.tif"),
    overwrite = TRUE
  )

  stand_matrix <- terra::as.matrix(forest_type_rast, wide = TRUE)
  write.table(
    stand_matrix,
    file.path(output_dir, "stand_grid.txt"),
    col.names = FALSE,
    row.names = FALSE
  )
}

# load up the dictionary from step 8
sapling_dictionary <- read.table(here("data", "empirical", "sapinit_dict.txt"), header = TRUE, sep = ",")
set.seed(1984)

dirs <- list.dirs(here(), recursive = FALSE)
landscape_dirs <- dirs[grepl("landscape_", basename(dirs))]
# Loop over the landscapes to create their stand_grid files
lapply(landscape_dirs, process_stand_grid, year_lyr = 1, sapinit_dict = sapling_dictionary)
