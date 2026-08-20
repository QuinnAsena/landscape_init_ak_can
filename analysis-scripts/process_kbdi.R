# 12 replicate spin-ups were run for all 6 landscapes using a default KBDI
# value of <KBDIref>0.038</KBDIref>.
# Using the spin-up with the closest match to the historic fire regime
# future scenarios spanning 2015-20100 (86 years) were run, as well as
# historic scenarios 1950-2015 (66 years) saving KBDI anually.
# After looking through the results, it was decided that a landscape-specific
# KBDI value derived from the historic runs would improve fire probabilities
# This script calculates a landscape-sprcific KBDI value from the
# historic scenario.

library(terra)
library(tidyr)
library(dplyr)
library(here)

dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])

landscape_cond <- "_onlyfire"
scenario <- "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120_onlyfire_historic"

kbdi_summary <- lapply(landscape_names, function(x) {
  out_dir <- here(x, "supporting_data", "kbdi_summary")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  # env.grid for mask
  env_grid_path <- here(x, "gis", "env.grid.tif")
  kbdi_path <- list.files(here(x, "output", paste(x, landscape_cond, sep = ""),
                               scenario, "rep_1", "kbdi"), full.names = TRUE)
  # Remove zeroth year as a raster of all zeros. That file was written by a
  # stray top-level onYearEnd(Globals.year) call in saveWorkflow.js, which fired
  # at script-parse time before the model had run. The call was removed on
  # 2026-08-19, so runs after that date have no kbdi_0.txt and this is a no-op.
  kbdi_path <- kbdi_path[!grepl("kbdi_0.txt$", kbdi_path)]
  # Order by model year. list.files sorts alphabetically, which interleaves
  # kbdi_1, kbdi_10, kbdi_11 ... -- harmless for a pooled average but it would
  # scramble the per-year output below.
  years <- as.integer(sub("^kbdi_", "", sub("[.]txt$", "", basename(kbdi_path))))
  kbdi_path <- kbdi_path[order(years)]
  years <- sort(years)
  # Read rasters
  env_grid <- rast(env_grid_path)
  kbdi_rast <- rast(kbdi_path)
  # give the kbdi raster the same CRS as the env.grid raster
  crs(kbdi_rast) <- crs(env_grid)

  # Zeros are unsimulated resource units, not dry ground. Verified 2026-08-20 on
  # landscape 04: KBDI > 0 if and only if the RU has at least one valid stand-grid
  # cell (1584/1584 zero cells had none; 0/60666 non-zero cells lacked one). The
  # 99 climate tables behind the zero cells are all also used by non-zero cells,
  # so climate cannot explain them -- ~33% of their days exceed the 10 C dQ
  # threshold, peaking at 32 C. Dropping zeros therefore selects exactly the
  # simulated RUs, which is why no mask() is needed: env.grid is only a partial
  # proxy, since it contains RUs the stand grid never covers.
  #
  # A climate-driven zero is possible in principle (dQ is 0 below 10 C or under
  # snow), which would make dropping zeros discard real data. It does not occur
  # here: the zero set is identical in every layer, with no cell zero in only
  # some years. n_zero_partial below audits that on every run -- if it is ever
  # > 0 in a colder run, revisit this.
  vals <- terra::values(kbdi_rast)
  is_zero <- vals == 0
  n_zero_partial <- sum(rowSums(is_zero) > 0 & rowSums(is_zero) < ncol(is_zero))
  vals[is_zero] <- NA

  # Guard, not a mask: nothing non-zero may sit outside the env.grid footprint.
  # Zero-dropping cannot detect that case, and it would do most damage on
  # landscape 01 (CPCRW), where 61,927 cells lie outside the footprint.
  outside <- is.na(terra::values(env_grid)[, 1]) & !is.na(vals[, 1])
  if (any(outside)) {
    warning(x, ": ", sum(outside), " non-zero cells outside the env.grid footprint")
  }

  # Spatial average per model year: one landscape-wide value per grid
  annual_mean <- colMeans(vals, na.rm = TRUE)
  annual <- data.frame(landscape = x, year = years, kbdi_mean = annual_mean,
                       row.names = NULL)
  write.csv(annual, file.path(out_dir, "kbdi_annual_mean.csv"), row.names = FALSE)

  # Pooled over every cell and every year -- this is the landscape KBDI value.
  # Quantiles come from the pooled cell-years, so they describe the full
  # spatial + temporal spread rather than the spread of the annual means.
  pooled <- as.vector(vals)
  pooled <- pooled[!is.na(pooled)]
  qs <- quantile(pooled, probs = c(0.25, 0.5, 0.75), names = FALSE)

  summary_row <- data.frame(
    landscape   = x,
    n_years     = length(years),
    n_cells     = sum(!is.na(vals[, 1])),
    # must stay 0: cells zero in only some years would be genuine dry-zero data
    n_zero_partial = n_zero_partial,
    kbdi_mean   = mean(pooled),
    kbdi_median = qs[2],
    kbdi_sd     = sd(pooled),
    kbdi_min    = min(pooled),
    kbdi_max    = max(pooled),
    kbdi_q25    = qs[1],
    kbdi_q75    = qs[3],
    kbdi_iqr    = qs[3] - qs[1],
    # spread of the annual landscape means -- interannual, not within-year
    annual_min  = min(annual_mean),
    annual_max  = max(annual_mean),
    annual_sd   = sd(annual_mean)
  )
  write.csv(summary_row, file.path(out_dir, "kbdi_summary.csv"), row.names = FALSE)
  summary_row
}) |>
  dplyr::bind_rows()

out_all <- here("data", "kbdi_summary")
dir.create(out_all, recursive = TRUE, showWarnings = FALSE)
write.csv(kbdi_summary, file.path(out_all, "kbdi_summary.csv"), row.names = FALSE)
