# =============================================================================
# NOTES ADDED 2026-09-16 -- why this script failed, and how to fix it
#
# Context: this script gave up on programmatic download ("Downloaded the whole
# dataset to Z") because of an endless redirect loop. That problem is now
# diagnosed and solved. A working reference implementation against the same
# ORNL_CLOUD archive is:
#     D:/quinn/GitHub/JFSP_FireManagement/quinn/download_boreal_tcc.R
#
# ---- 1. THE INFINITE REDIRECT (the reason this script was abandoned) --------
# Earthdata Login authenticates over an OAuth redirect chain:
#     protected URL -> urs.earthdata.nasa.gov -> back to the app -> S3
# The app sets a SESSION COOKIE partway through. With no cookie jar, curl
# discards it, so the app bounces straight back to URS, forever.
#
# Reproduced and fixed, verified 2026-09-01:
#     curl -n -L URL                        -> exit 47, 20 redirects, 0 bytes
#     curl -n -L -c jar.txt -b jar.txt URL  -> exit  0,  4 redirects, correct bytes
#
# So the fix in this script is to add a cookie jar to the curl calls around
# line 120:
#     curl -L --netrc -c cookies.txt -b cookies.txt "URL" -o "OUT"
#
# It is NOT a credentials problem. And --location-trusted is NOT the fix --
# that would send your password on to S3.
#
# For GDAL/terra the equivalent is GDAL_HTTP_COOKIEFILE + GDAL_HTTP_COOKIEJAR;
# without them terra::rast(href, vsi=TRUE) fails the same way, which is why the
# earthdatalogin attempt in earthdata_support.r also came to nothing.
#
# ---- 2. .netrc MUST BE ANCHORED ON THE PROFILE, NOT HOME -------------------
# Verified 2026-09-16. There were TWO .netrc files on this machine with
# DIFFERENT usernames:
#     C:/Users/asenaq/.netrc            3 lines, 10-char login -> HTTP 206 (works)
#     C:/Users/asenaq/Documents/.netrc  1 line,   8-char login -> HTTP 401
# Rscript from a shell resolves HOME to the profile and picks the good one, but
# an IDE-launched R session resolves HOME (and "~") to Documents and picks the
# bad one -- so every download 401s, with valid credentials.
#
# The Documents one has since been deleted. To avoid this class of bug, pass the
# path explicitly instead of relying on discovery:
#     curl --netrc-file "C:/Users/asenaq/.netrc" ...
# or in R:  curl::handle_setopt(h, netrc = TRUE, netrc_file = <path>)
# Anchor on Sys.getenv("USERPROFILE"), never on "~".
#
# ---- 3. CMR PAGING -- THIS SCRIPT IS SILENTLY TRUNCATING ITS RESULTS -------
# Verified 2026-09-01. CMR caps page_size at 2000. The request below uses
# page_size = 2000 and reads a single response, so if a query matches more than
# 2000 granules it returns the first 2000 with NO error and NO warning.
# For scale: the Boreal_CanopyCover_StandAge collection has 8,414 granules over
# North America, so such a query would silently lose ~75% of its results.
# Fix: follow the CMR-Search-After response header and keep requesting until a
# page comes back short. See find_granules() in download_boreal_tcc.R.
#
# ---- 4. SECURITY: PLAINTEXT PASSWORD STILL IN THIS FILE --------------------
# There is a hardcoded Earthdata password below (in the MoreArgs list, and again
# in the commented block near the bottom), on a shared network drive. The
# password was rotated on 2026-09-16 so the value is now stale, but it should be
# deleted rather than left lying around, and the username/password arguments
# dropped entirely -- .netrc makes them unnecessary.
#
# ---- 5. STATUS --------------------------------------------------------------
# Notes only; no code changed. The fixes above are understood and tested
# elsewhere, but this script has NOT been updated yet.
# =============================================================================


# Downloading data from ORNL CLOUD specifically gave issues.
# Other DACs seems accessible programatically more easily
# Downloaded the whole dataset to Z, it is not that large

# Authentication:
# from Bash (on windows) nano ~/.netrc
# write:
# machine urs.earthdata.nasa.gov
# login YOUR_USERNAME
# password YOUR_PASSWORD
# check authentication:
# curl_fetch_memory(
#   "https://daac.ornl.gov",
#   handle = new_handle(netrc = TRUE)
# )

# library(curl)
# library(jsonlite)
library(terra)
library(sf)
library(httr2)
library(future.apply)


dirs <- normalizePath(list.dirs(full.names = TRUE))
ak_landscape_dirs <- dirs[grepl(".*[\\\\/]landscape_[0-9]+$", dirs)]

landscape_ord <- as.integer(
  sub(".*landscape_([0-9]+).*$", "\\1", ak_landscape_dirs)
)
ord <- order(landscape_ord)
ak_landscape_dirs <- ak_landscape_dirs[ord]

# Get bounding boxes from original download
env_files <- list.files(
  path = ak_landscape_dirs, 
  pattern = "env.grid.tif$", full.names = TRUE, recursive = TRUE)


ak_landcapes <- lapply(env_files, function(x) {
  rast(x)
})

bboxes <- lapply(ak_landcapes, \(landscape){
  bbox <- as.polygons(ext(landscape), crs = crs(landscape)) |>
    st_as_sf() |>
    sf::st_transform(4326) |>
    sf::st_bbox() |>
    as.numeric()
  bbox
})

concept_ids <- c(
    Decadal_Water_Maps_1324 = "C2162118169-ORNL_CLOUD",
    Annual_Landcover_ABoVE_1691 = "C2143403402-ORNL_CLOUD")




# https://www.earthdata.nasa.gov/data/catalog/ornl-cloud-decadal-water-maps-1324-1.1
# https://www.earthdata.nasa.gov/data/catalog/ornl-cloud-annual-landcover-above-1691-1

bbox <- paste(bboxes[[1]], collapse = ",")
username = "quinnasena"
password = "7BGrZ/4KSj.K^B,"
out_loc <- ak_landscape_dirs[1]
concept_id <- concept_ids[[1]]
concept_name <- names(concept_ids[1])

download_above <- function(bbox, username, password, out_loc, concept_id, concept_name) {
  # Request tiles based on bounding box (returns urls)
  outdir <- file.path(out_loc, concept_name)
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

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

  urls <- vapply(meta$feed$entry,
    function(x) {
      x$links[[1]]$href
    }, character(1))

  if (concept_name == "Annual_Landcover_ABoVE_1691") {
    urls <- urls[grepl("\\.tif", urls)]
    urls <- urls[!grepl("Simplified", urls)]
  }
  
  if (concept_name == "Decadal_Water_Maps_1324") {
    urls <- urls[!grepl("QA", urls)]
  }


  os_type <- Sys.info()["sysname"]
  
  lapply(urls, \(u) {
    if (file.exists(file.path(outdir, basename(u)))) {
      warning("Tile already present. Skipping download.")
      return(invisible(NULL))
    }

    outfile <- file.path(outdir, basename(u))
    
    if (os_type %in% c("Linux", "Darwin")) {
      cmd <- sprintf(
        'wget --netrc "%s" -O "%s"',
        u, outfile
      )
    } else {
      cmd <- sprintf(
        'curl -L --netrc "%s" -o "%s"',
        u, outfile
      )
    }

    # if (os_type %in% c("Linux", "Darwin")) {
    #   cmd <- sprintf(
    #     'wget --user=%s --password=%s --no-check-certificate "%s" -O "%s"',
    #     username, password, u, outfile
    #   )
    # } else {
    #   cmd <- sprintf(
    #     'curl -u %s:%s "%s" -o "%s" -L',
    #     username, password, u, outfile
    #   )
    # }
    # system(cmd)

   status <- system(cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)

   if (status != 0 || file.info(outfile)$size < 5000) {
     warning("Download likely failed: ", basename(outfile))
   }

  })
}



download_params <- expand.grid(
  bbox_index  = seq_along(bboxes),
  concept_name = names(concept_ids),
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)

download_params$bbox <- bboxes[download_params$bbox_index]
download_params$concept_id <- concept_ids[download_params$concept_name]
download_params$out_loc <- ak_landscape_dirs[download_params$bbox_index]

plan(multisession, workers = 5)

future_mapply(
  FUN = download_above,
  bbox = download_params$bbox,
  out_loc = download_params$out_loc,
  concept_id = download_params$concept_id,
  concept_name = download_params$concept_name,
  MoreArgs = list(username = "quinnasena", password = "7BGrZ/4KSj.K^B,"),
  SIMPLIFY = FALSE, future.seed = TRUE
)

plan(sequential)



# for (i in seq_along(concept_ids)) {
#    print(names(concept_ids[1]))
# }


# download_above <- function(bbox, username, password, out_loc, concept_id) {
# # Request tiles based on bounding box (returns urls)
#   outdir <- file.path(out_loc, names(concept_id))
#   dir.create(outdir, recursive = TRUE)

#   req <- request(
#     "https://cmr.earthdata.nasa.gov/search/granules.json"
#   ) |>
#     req_url_query(
#       concept_id = concept_id,
#       bounding_box = paste(bbox, collapse = ","),
#       page_size = 2000
#     )

#   res <- req_perform(req)
#   meta <- resp_body_json(res)

#   urls <- vapply(meta$feed$entry,
#     function(x) {
#       x$links[[1]]$href
#     }, character(1))

#   if (names(concept_id) == "Annual_Landcover_ABoVE_1691") {
#     urls <- urls[grepl("\\.tif", urls)]
#     urls <- urls[!grepl("Simplified", urls)]}

#   os_type <- Sys.info()["sysname"]
#   # For mac/linux
#   if (os_type %in% c("Linux", "Darwin")) {
#     lapply(urls, \(u) {

#       if (file.exists(file.path(outdir, basename(u)))) {
#         warning("ABoVR tiles already present. Skipping download.")
#         return(invisible(NULL))}

#       fname <- basename(u)
#       cmd <- sprintf(
#         'wget --user=%s --password=%s --no-check-certificate "%s" -O "%s"',
#         username, password, u, file.path(outdir, fname)
#       )
#       result <- system(cmd)
#     })
    
#     } else if (os_type == "Windows") {
#     # For windows is wget is not installed
#       lapply(urls, \(u) {
#         if (file.exists(file.path(outdir, basename(u)))) {
#           warning("ABoVR tiles already present. Skipping download.")
#           return(invisible(NULL))}

#         fname <- basename(u)
#         cmd <- sprintf(
#           'curl -u %s:%s "%s" -o "%s" -L',
#           username, password, u, file.path(outdir, fname)
#         )
#         result <- system(cmd)
#       })
#     }
# }


# plan(multisession, workers = 5)

# future_mapply(
#   FUN = download_above,
#   bbox = bboxes,
#   out_loc = ak_landscape_dirs,
#   MoreArgs = list(username = "quinnasena", password = "7BGrZ/4KSj.K^B,"),
#   SIMPLIFY = FALSE
# )

# plan(sequential)

