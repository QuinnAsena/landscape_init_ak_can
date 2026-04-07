# This script will install packages and dependencies required for the
# pipeline. They will also be loaded.

if (!requireNamespace("pak", quietly = TRUE)) {
  install.packages("pak", repos = "http://cran.r-project.org")
}

paks <- c(
  # Spatial
  "terra",
  "sf",
  "rstac",    # STAC API for ArcticDEM download (step 05)
  "geodata",  # SoilGrids download (step 05b)
  # Data wrangling
  "dplyr",
  "tidyr",
  "purrr",
  "lubridate",
  # Statistics
  "fitdistrplus",  # Distribution fitting for stand initialisation (step 08)
  # Database
  "DBI",
  "RSQLite",
  # Utilities
  "here",
  "future.apply"
  # Exploratory / supporting scripts (not required for main pipeline)
  # "httr2",          # ABoVE download, earthdata authentication
  # "gdalcubes",      # earthdata_support.r
  # "earthdatalogin", # earthdata_support.r
  # "ggplot2",        # cpcrw_test.r
  # "patchwork",      # cpcrw_test.r
  # "httpgd",         # cpcrw_test.r (graphics device)
  # "tidyverse"       # landscape_selection.r
)

pak::pak(paks)

lapply(paks, library, character.only = TRUE)
