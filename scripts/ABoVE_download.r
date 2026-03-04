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

