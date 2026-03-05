library(terra)
library(sf)
library(rstac)
library(here)

# This is my script to pull DEM data from Arctic DEM
# Load in env.grids as templates
dirs <- normalizePath(list.dirs(full.names = TRUE))
ak_landscape_dirs <- dirs[grepl(".*[\\\\/]landscape_[0-9]+$", dirs)]

# make sure landscapes are ordered
landscape_id <- as.integer(
  sub(".*landscape_([0-9]+)$", "\\1", ak_landscape_dirs)
)
ord <- order(landscape_id)
ak_landscape_dirs <- ak_landscape_dirs[ord]

env_files <- list.files(path = ak_landscape_dirs, 
                        pattern = "env.grid.tif$", full.names = TRUE, recursive = TRUE)

landscape_names <- sub(".*(landscape_[0-9]+).*", "\\1", env_files)


ak_landcapes <- lapply(env_files, function(x) {
  rast(x)
})

download_dem <- function(landscape, landscape_name) {

  outdir <- here(landscape_name, "gis", "dem", "arcticdem_10m")
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

  stac_url <- "https://stac.pgc.umn.edu/api/v1/"
  stac_api <- stac(stac_url)
  # Find available collections
  collections_query <- stac_api |>
    rstac::collections()
  # Print available collections
  rstac::get_request(collections_query)
  # Get a bounding box per landscape in the correct crs for stac query (4326)
  bbox_4326 <- as.polygons(ext(landscape), crs = crs(landscape)) |>
    st_as_sf() |>
    sf::st_transform(4326) |>
    sf::st_bbox() |>
    as.numeric()
  bbox_4326
  # Define a STAC query to find items in the "arcticdem-mosaics-v4.1-10m"
  stac_query <- stac_search(
    stac_api,
    collections = "arcticdem-mosaics-v4.1-10m",
    bbox = bbox_4326
  ) |>
    post_request() |>
    items_fetch()

  # signed_stac_query <- rstac::items_sign(
  #   executed_stac_query,
  #   rstac::sign_planetary_computer()
  # )
  # signed_stac_query
  # urls <- assets_url(stac_query, asset_names = "dem")

  tile_ids <- vapply(stac_query$features, function(x) x$id, character(1))
  tile_base <- file.path(outdir, "arcticdem", "mosaics", "v4.1", "10m")
  #tile_dirs <- sub("_10m_v4\\.1$", "", tile_ids)

  if (dir.exists(tile_base) &&
    length(list.files(tile_base, recursive = TRUE)) > 0) {
    warning("ArcticDEM tiles already present. Skipping download.")
    return(invisible(NULL))
  }

  assets_download(stac_query,
                  asset_names = c("dem", "hillshade", "maxdate", "mindate", "metadata"),
                  output_dir = outdir)
}

#--------------- Run the function ---------------#

Map(download_dem, ak_landcapes, landscape_names)
