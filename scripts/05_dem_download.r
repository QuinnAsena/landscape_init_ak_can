library(terra)
library(sf)
library(rstac)
library(here)

# Downloads ArcticDEM mosaic tiles (v4.1, 10m resolution) for each landscape
# using the STAC API. A 1000m buffer is applied to the landscape extent before
# querying to ensure full tile coverage at the landscape boundary — this
# supports aspect calculation in step 06 without NA border values.
dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])

download_dem <- function(landscape_name) {

  outdir <- here(landscape_name, "supporting_data", "gis", "dem", "arcticdem_10m")
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

  env_file <- list.files(here(landscape_name, "gis"),
                         pattern = "env.grid.tif$", full.names = TRUE)
  landscape <- rast(env_file)
  landscape <- terra::buffer(as.polygons(landscape, extent = TRUE), width = 1000)

  stac_url <- "https://stac.pgc.umn.edu/api/v1/"
  stac_api <- stac(stac_url)
  # Find available collections
  # collections_query <- stac_api |> rstac::collections()
  # rstac::get_request(collections_query)
  # STAC requires a WGS84 bounding box — transform from the landscape CRS
  bbox_4326 <- as.polygons(ext(landscape), crs = crs(landscape)) |>
    st_as_sf() |>
    sf::st_transform(4326) |>
    sf::st_bbox() |>
    as.numeric()
  # Query the ArcticDEM STAC catalogue for 10m mosaic tiles intersecting the bbox
  stac_query <- stac_search(
    stac_api,
    collections = "arcticdem-mosaics-v4.1-10m",
    bbox = bbox_4326
  ) |>
    post_request() |>
    items_fetch()

  tile_ids <- vapply(stac_query$features, function(x) x$id, character(1))
  tile_base <- file.path(outdir, "arcticdem", "mosaics", "v4.1", "10m")

  if (dir.exists(tile_base) &&
    length(list.files(tile_base, recursive = TRUE)) > 0) {
    warning("ArcticDEM tiles already present. Skipping download.")
    return(invisible(NULL))
  }

  assets_download(stac_query,
                  asset_names = c("dem", "hillshade", "maxdate",
                                  "mindate", "metadata"),
                  output_dir = outdir)
}

#--------------- Run the function ---------------#

lapply(landscape_names, download_dem)
