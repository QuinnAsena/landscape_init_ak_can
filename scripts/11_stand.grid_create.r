#---------- Create stand grid rasters for each landscape ----------#

# Assigns a random stand_id to every forested RU cell based on the forest species
# class from step 07 and the stand dictionary from step 08.
# "Potential forest" cells (class 6) are assigned an out-of-range value so iLand
# can identify them as unforested but potentially recruitable pixels.
# Outputs stand_grid.tif and stand_grid.txt (ASCII) for iLand.
library(terra)
library(here)
library(future.apply)

process_stand_grid <- function(landscape_name, year_lyr, sapinit_dict) {
  in_dir <- here(landscape_name, "supporting_data", "gis", "init")
  output_dir <- here(landscape_name, "gis")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  forest_type_rast <- rast(
    file.path(in_dir, paste0("forest_species_init_lc_yr", year_lyr, ".tif"))
  )

  # Recode class 6 (potential forest) to one above the maximum stand_id so it
  # falls outside the range of any real stand and can be identified by iLand
  forest_type_rast <- ifel(
    forest_type_rast == 6, max(sapinit_dict$max_stand_id) + 1,
    forest_type_rast
  )

  # Randomly scatter stand IDs across the landscape. Each cell is assigned a
  # stand_id drawn from the range defined in the dictionary for its forest class,
  # ensuring species composition is drawn from the correct empirical distribution.
  # orig_vals holds the original forest class codes throughout — without this,
  # bene stand_ids (1–16) overlap with other forest class codes (1, 2, 3) and
  # those pixels would be incorrectly overwritten in later iterations.
  orig_vals <- terra::values(forest_type_rast)
  new_vals  <- orig_vals
  for (i in seq_len(nrow(sapinit_dict))) {
    idx <- which(orig_vals == sapinit_dict$forest_class[i])
    new_vals[idx] <- sample(
      sapinit_dict$min_stand_id[i]:sapinit_dict$max_stand_id[i],
      size = length(idx), replace = TRUE)
  }
  values(forest_type_rast) <- new_vals

  # NA cells (non-forest/water) are set to -9999 as the iLand no-data value.
  # The documentation specifies -1 but -9999 is also accepted.
  forest_type_rast <- ifel(is.na(forest_type_rast), -1, forest_type_rast)

  writeRaster(
    forest_type_rast,
    file.path(output_dir, paste0("stand_grid_yr", year_lyr, ".tif")),
    overwrite = TRUE, datatype = "INT4S", NAflag = -1
  )

  writeRaster(
    forest_type_rast,
    file.path(output_dir, paste0("stand_grid_yr", year_lyr, ".txt")),
    overwrite = TRUE, filetype = "AAIGrid", datatype = "INT4S", NAflag = -1
  )
}

# Load the stand dictionary produced in step 08: maps forest class codes to
# min/max stand_id ranges used for random assignment
sapling_dictionary <- read.table(
  here("data", "empirical", "sapinit_dict.txt"),
  header = TRUE, sep = ",")
set.seed(1984)

dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])

# Run for land cover year 1 (1984) — re-run with different year_lyr as needed
lapply(landscape_names, process_stand_grid,
              year_lyr = 1, sapinit_dict = sapling_dictionary)

lapply(landscape_names, process_stand_grid,
              year_lyr = 31, sapinit_dict = sapling_dictionary)