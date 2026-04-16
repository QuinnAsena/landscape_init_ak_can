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
                             desired_years, mod_years, filt_cond, seed) {
  x <- read_xml(as.character(master_xml))
  out_xml <- here(landscape_name, paste0(landscape_name, "_", run_type, ".xml"))

  env_file <- list.files(here(landscape_name, "gis"),
                         pattern = "env.grid.tif$", full.names = TRUE)
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
  editxml(x, "//climate/randomSamplingList", climate_settings$random_sample_list)
  editxml(x, "//climate/batchYears", as.character(climate_settings$batch_years))

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
  
  save_filter <- paste0("year >= ", mod_years - filt_cond, " and year <= ", mod_years)
  # Set save conditions
  editxml(x,"//output/tree/filter", save_filter)
  editxml(x,"//output/stand/condition", save_filter)
  editxml(x,"//output/sapling/condition", save_filter)
  editxml(x,"//output/saplingdetail/condition", save_filter)
  editxml(x,"//output/carbon/condition", save_filter)
  editxml(x,"//output/water/condition", save_filter)

  write_xml(x, out_xml)
}

gen_project_file(
    landscape_name = landscape_names[1],
    master_xml = master_xml,
    run_type = "spinup",
    desired_years = 1950:1980,
    mod_years = 300,
    filt_cond = 260,
    seed = 1984)



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
