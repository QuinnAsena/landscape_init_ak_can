library(here)
library(xml2)
library(terra)


dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])

#--------------- helper functions ---------------#
# helper function to edit xml nodes
editxml <- function(xmlfile, tag, value) {
  # tag is a character (xpath) that returns one node.
  # value is the desired value of the node (character)
  tomod <- xml_find_all(xmlfile, tag)
  if (length(tomod) == 1) {
    xml_text(tomod) <- value
  } else {
    warning("Found ", length(tomod), " nodes for '", tag,
            "'. Re-specify tag to find exactly 1. No edit made.")
  }
}

# helper function to sample climate years for model runs
sample_climate <- function(desired_years = 1950:1980, mod_years = 300, seed = 1984) {
  set.seed(seed) # always set the seed for reproducibility
  batch_years <- length(desired_years) # length of historic climate to resample
  # zero-indexed vector of random years to sample from the climate data
  # (e.g., 0 = first year of desired_years, 1 = second year, etc.)
  resample_vector <- sample(0:(batch_years - 1), mod_years, replace = TRUE)
  climate_filter <- paste0("year >= ", min(desired_years), " and year <= ", max(desired_years))
  random_sample_list <- paste(resample_vector, collapse = ",")
  list(climate_filter    = climate_filter,
       random_sample_list = random_sample_list,
       batch_years        = batch_years)
}

#--------------- main function to generate project file ---------------#

master_xml <- read_xml(here("data", "shared-xml-create", "landscape_master.xml"))

gen_project_file <- function(landscape_name, master_xml, run_type,
                             desired_years, mod_years, filt_cond,
                             save_tree, save_stand, save_sapling,
                             save_saplingdetail, save_carbon, save_water,
                             seed, note) {
  x <- read_xml(as.character(master_xml))

  env_file <- list.files(here(landscape_name, "gis"),
                         pattern = "env.grid.tif$", full.names = TRUE)
  if (length(env_file) == 0) {
    env_file <- list.files(paste0(
    "//10.60.2.10/FF_Lab/personal_storage/quinn_storage/landscape_init_ak_can/", landscape_name, "/gis/"),
    pattern = "env.grid.tif$", full.names = TRUE)
  }

  env_grid <- rast(env_file)

  wid <- ncol(env_grid) * 100
  hig <- nrow(env_grid) * 100
  xllcorner <- xmin(env_grid)
  yllcorner <- ymin(env_grid)
  latitude <- round(crds(
    project(
      vect(cbind(mean(c(xmin(env_grid), xmax(env_grid))),
                 mean(c(ymin(env_grid), ymax(env_grid)))),
           crs = crs(env_grid)), "EPSG:4326"
    )
  )[, "y"])

  # set-up world
  editxml(x, "//world/width", as.character(wid)) #horizontal (east-west) extent of the simulation area (m)
  editxml(x, "//world/height", as.character(hig)) #vertical (north-south) extent (meter)
  editxml(x, "//world/latitude", as.character(latitude))
  editxml(x, "//location/x", as.character(xllcorner))
  editxml(x, "//location/y", as.character(yllcorner))

  # Set up climate sampling
  climate_settings <- sample_climate(desired_years, mod_years, seed)
  editxml(x, "//climate/filter", climate_settings$climate_filter)
  editxml(x, "//climate/randomSamplingList", paste0('"', climate_settings$random_sample_list, '"'))
  editxml(x, "//climate/batchYears", as.character(climate_settings$batch_years))
  # leave 'file' blank include a blank entry in scenario csv.
  # iLand might print a warning, that no file is found but that's fine.
  if (run_type == "spinup") {
    mode <- "standgrid"
    type <- "distribution"
    file <- ""
  } else if (run_type == "scenario") {
    mode <- "snapshot"
    type <- "iland"
    file <- "overwritten_by_csv"
  } else {
    stop("Unknown run_type '", run_type, "'. Expected 'spinup' or 'scenario'.")
  }

  # Set up model type e.g., spinup vs. not
  editxml(x,"//initialization/mode", mode)
  editxml(x,"//initialization/type", type)
  editxml(x,"//initialization/file", file)

  # save outputs individually per output type
  # currently fire outputs are always true
  outputs <- list(
    tree          = save_tree,
    stand         = save_stand,
    sapling       = save_sapling,
    saplingdetail = save_saplingdetail,
    carbon        = save_carbon,
    water         = save_water
  )
  # tree uses "filter", the rest use "condition" for the year-filter tag
  filter_tag <- c(tree = "filter", stand = "condition", sapling = "condition",
                  saplingdetail = "condition", carbon = "condition", water = "condition")

  # This defines the filter for which years to save in the following tags
  # use -1 to actively blank the filter tag instead of leaving it untouched
  filter_value <- if (filt_cond == -1) {
    ""
  } else {
    paste0("year >= ", filt_cond, " and year <= ", mod_years)
  }

  for (out_name in names(outputs)) {
    enabled <- outputs[[out_name]]
    if (!isTRUE(enabled) && !isFALSE(enabled)) {
      stop("save_", out_name, " must be TRUE or FALSE")
    }
    editxml(x, paste0("//output/", out_name, "/enabled"), tolower(as.character(enabled)))
    editxml(x, paste0("//output/", out_name, "/", filter_tag[[out_name]]), filter_value)
  }

  out_xml <- here(landscape_name,
    paste0(landscape_name, "_",
    paste0(range(desired_years), collapse = "-"),
    run_type, note, ".xml"))

  write_xml(x, out_xml)
}


#--------------- Generate spinup files for all landscapes ---------------#
# Complete
# for (i in seq_along(landscape_names)) {
#   gen_project_file(
#     landscape_name     = landscape_names[i],
#     master_xml         = master_xml,
#     run_type           = "spinup",
#     save_tree          = TRUE,
#     save_stand         = TRUE,
#     save_sapling       = TRUE,
#     save_saplingdetail = TRUE,
#     save_carbon        = TRUE,
#     save_water         = TRUE,
#     desired_years      = 1950:1980,
#     mod_years          = 300,
#     filt_cond          = 260,
#     seed               = 1984 + i,
#     note               = ""
#   )
# }

#--------------- Generate future fire xml files for all landscapes ---------------#
# Complete
# for (i in seq_along(landscape_names)) {
#   gen_project_file(
#     landscape_name     = landscape_names[i],
#     master_xml         = master_xml,
#     run_type           = "scenario",
#     save_tree          = FALSE,
#     save_stand         = FALSE,
#     save_sapling       = FALSE,
#     save_saplingdetail = FALSE,
#     save_carbon        = FALSE,
#     save_water         = FALSE,
#     desired_years      = 2015:2100,
#     mod_years          = 86,
#     filt_cond          = -1,
#     seed               = 1984 + i,
#     note = "_onlyfire")
# }

#--------------- Generate future scenario xml files for all landscapes ---------------#
for (i in seq_along(landscape_names)) {
  gen_project_file(
    landscape_name     = landscape_names[i],
    master_xml         = master_xml,
    run_type           = "scenario",
    save_tree          = FALSE,
    save_stand         = TRUE,
    save_sapling       = FALSE,
    save_saplingdetail = TRUE,
    save_carbon        = TRUE,
    save_water         = TRUE,
    desired_years      = 2015:2100,
    mod_years          = 86,
    filt_cond          = -1,
    seed               = 1984 + i,
    note = "")
}
#---------------


##--------------- Move shared files to landscapes ---------------#
shared <- here("data", "shared-xml-create")

check_copy <- function(ok, label) {
  if (!all(ok)) warning("File copy failed for: ", label)
}

lapply(landscape_names, function(lcp) {
  
  sub_dirs <- c("databases", "temp", "log", "output", "snapshot")
  lapply(sub_dirs, \(dir) {
    dir.create(here(lcp, dir), recursive = TRUE, showWarnings = FALSE)
  })

  # 1. Copy lip/ directory into each landscape root
  check_copy(
    file.copy(file.path(shared, "lip"), here(lcp), recursive = TRUE, overwrite = TRUE),
    paste(lcp, "lip/")
  )

  # 2. Copy spp_param.sqlite into each landscape's databases/ directory
  check_copy(
    file.copy(file.path(shared, "spp_param.sqlite"),
              here(lcp, "databases", "spp_param.sqlite"), overwrite = TRUE),
    paste(lcp, "spp_param.sqlite")
  )

  # 3. Create scripts/ directory and copy saveWorkflow.js into it
  dir.create(here(lcp, "scripts"), recursive = TRUE, showWarnings = FALSE)
  check_copy(
    file.copy(file.path(shared, "saveWorkflow.js"),
              here(lcp, "scripts", "saveWorkflow.js"), overwrite = TRUE),
    paste(lcp, "saveWorkflow.js")
  )
})
