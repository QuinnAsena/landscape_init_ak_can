library(here)
library(xml2)
library(terra)


dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])

# helper function to edit xml nodes
editxml <- function(xmlfile, tag, value){
  #tag is a character (xpath) that returns one node.
  #value is the desired value of the node (character)
  tomod <- xml_find_all(xmlfile, tag)
  if(length(tomod) == 1) { #you found (only) one node
    xml_text(tomod) <- value #replace the value
    print("After the edit:")
    print(xml_find_all(xmlfile, tag)) #This is what it looks like after the edit
  }
  if(length(tomod) != 1) {
    print(paste0("You found ",length(tomod)," nodes. Re-specify tag to find 1. No edits made"))
  }
}

# helper function to sample climate years for model runs
sample_climate <- function(climate_span = 1950:2100, desired_years = 1950:1980, mod_years = 300, seed = 1984) {
  set.seed(seed) # always set the seed for reproducibility
  batch_years <- length(desired_years) # length of historic climate to resample
  resample_vector <- sample(0:(batch_years - 1), mod_years, replace = TRUE) # zero-indexed vector of random years to sample from the climate data (e.g., 0 = 1950, 1 = 1951, etc.)
  climate_filter <- paste0("year >= ", min(desired_years), " and year <= ", max(desired_years))
  random_sample_list <- paste(resample_vector, collapse = ",")
  return(list(climate_filter = climate_filter,
              random_sample_list = random_sample_list,
			  batch_years = batch_years))
}



master_xml <- read_xml(here("data", "shared-xml-create", "landscape_master.xml"))

gen_project_file <- function(landscape_name, master_xml, run_type,
                             climate_span, desired_years, mod_years,
                             filt_cond, seed) {
  x <- read_xml(as.character(master_xml))
  out_xml <- here(landscape_name, paste0(landscape_name, "_", run_type, ".xml"))

  env_file <- list.files(here(landscape_name, "gis"),
                         pattern = "env.grid.tif$", full.names = TRUE)
  env_grid <- rast(env_file)

  wid <- ncol(env_grid) * 100
  hig <- nrow(env_grid) * 100
  xllcorner <- ext(env_grid)[1]
  yllcorner <- ext(env_grid)[3]
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
  climate_settings <- sample_climate(climate_span, desired_years, mod_years, seed)
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



# move lip directories to each landscape

# move spp database to each landscape's database directory

# create scripts directory per landsacpe and copy javascripts there
