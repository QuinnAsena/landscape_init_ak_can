# ---------- METHOD 1 ---------- #
# Manual method:
# Create .netrc file for authentication
library(httr2)
netrc_path <- file.path(Sys.getenv("USERPROFILE"), ".netrc")
username <- "quinnasena"
password <- "***"
netrc_content <- sprintf("machine urs.earthdata.nasa.gov\nlogin %s\npassword %s\n", 
                         username, password)
writeLines(netrc_content, netrc_path)
Sys.chmod(netrc_path, "0600")

# Datasets I am trying to download
concept_ids <- c(
    Decadal_Water_Maps_1324 = "C2162118169-ORNL_CLOUD",
    Annual_Landcover_ABoVE_1691 = "C2143403402-ORNL_CLOUD")

# define an area
bbox <- "-155.050913690133,62.362497478261,-154.302505034896,62.6956166510325"
# Going with single dataset for testing
concept_id <- concept_ids[[1]]
concept_name <- names(concept_ids[1])
# make an output directory
outdir <- file.path(Sys.getenv("USERPROFILE"), "Documents", concept_name)
dir.create(outdir)

req <- request(
    "https://cmr.earthdata.nasa.gov/search/granules.json"
  ) |>
    req_url_query(
      concept_id = concept_id,
      bounding_box = paste(bbox, collapse = ","),
      page_size = 2000
    )

res <- req_perform(req)
meta <- resp_body_json(res)
length(meta$feed$entry)

# seems to be retrieving urls 
urls <- vapply(meta$feed$entry,
  function(x) {
    x$links[[1]]$href
  }, character(1))

urls <- urls[!grepl("QA", urls)]

# Try with just one url
u <- urls[1]
outfile <- file.path(outdir, basename(u))

# Use curl with netrc
cmd <- sprintf(
  'curl -n -L "%s" -o "%s"',
  u, outfile
)
# Redirects 50 times...
system(cmd)


# ---------- METHOD 2 ---------- #
# earthdatalonin method from: https://boettiger-lab.github.io/earthdatalogin/articles/gdalcubes-stac-cog.html

library(rstac)
library(gdalcubes)
library(earthdatalogin)

gdalcubes_options(parallel = TRUE) 
edl_netrc()
with_gdalcubes()

# from: https://radiantearth.github.io/stac-browser/#/external/cmr.earthdata.nasa.gov/stac/ORNL_CLOUD/collections/Decadal_Water_Maps_1324_1.1
url <- "https://cmr.earthdata.nasa.gov/stac/ORNL_CLOUD"
collection <- "Decadal_Water_Maps_1324_1.1"

bbox <- "-155.050913690133,62.362497478261,-154.302505034896,62.6956166510325"

items <- stac(url) |> 
  stac_search(collections = collection,
              bbox = bbox) |>
  post_request() |>
  items_fetch()
  
href <- items$features[[1]]$assets[["tif"]]$href

r <- terra::rast(href, vsi=TRUE)
# nope!
