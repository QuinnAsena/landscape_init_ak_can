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

  # Set up climate sampling. The filter differs by run type, so it is set within
  # each branch alongside the sampling keys it belongs with -- climate_settings
  # only exists in the spinup branch.
  # leave 'file' blank include a blank entry in scenario csv.
  # iLand might print a warning, that no file is found but that's fine.
  if (run_type == "spinup") {
    mode <- "standgrid"
    type <- "distribution"
    file <- ""
    js_file <- "saveWorkflow_spinup.js"
    # resample the historic window across the full spinup length
    climate_settings <- sample_climate(desired_years, mod_years, seed)
    editxml(x, "//climate/filter", climate_settings$climate_filter)
    editxml(x, "//climate/randomSamplingEnabled", "true")
    editxml(x, "//climate/randomSamplingList", paste0('"', climate_settings$random_sample_list, '"'))
    editxml(x, "//climate/batchYears", as.character(climate_settings$batch_years))
  } else if (run_type == "scenario") {
    mode <- "snapshot"
    type <- "iland"
    file <- "overwritten_by_csv"
    js_file <- "saveWorkflow_scenario.js"
    # Read the projection sequentially, so the sampling list stays blank.
    # batchYears is only a climate read-buffer size here -- 50 years loaded at a
    # time rather than one, which avoids constant database queries. It is safe
    # for it to be smaller than the run length ONLY because sampling is off:
    # with randomSamplingEnabled=true it would also cap the climate to the first
    # batchYears of the record.
    editxml(x, "//climate/filter",
            paste0("year >= ", min(desired_years), " and year <= ", max(desired_years)))
    editxml(x, "//climate/randomSamplingEnabled", "false")
    editxml(x, "//climate/randomSamplingList", "")
    editxml(x, "//climate/batchYears", "50")
  } else if (run_type == "historic") {
    # Starts from the spinup snapshot, exactly like the scenario runs, so the CSV
    # must supply snapshot_file (see iland_scenarios_onlyfire_historic.csv). What
    # differs from 'scenario' is only the climate window: the real 1950-2015
    # record read in sequence rather than the 2015-2100 projection, so the run
    # follows the observed order of fire weather.
    #
    # Functionally this branch is now the scenario branch with a different
    # batchYears, and both values are only read-buffer sizes. It is kept separate
    # so the run type is explicit in the output filename.
    mode <- "snapshot"
    type <- "iland"
    file <- "overwritten_by_csv"
    js_file <- "saveWorkflow_scenario.js"
    editxml(x, "//climate/filter",
            paste0("year >= ", min(desired_years), " and year <= ", max(desired_years)))
    editxml(x, "//climate/randomSamplingEnabled", "false")
    editxml(x, "//climate/randomSamplingList", "")
    # Read-buffer size only, because sampling is off (see the scenario branch).
    # Derived from desired_years so it cannot drift out of step with the filter.
    editxml(x, "//climate/batchYears", as.character(length(desired_years)))
  } else {
    stop("Unknown run_type '", run_type,
         "'. Expected 'spinup', 'scenario' or 'historic'.")
  }

  # Set up model type e.g., spinup vs. not
  editxml(x,"//initialization/mode", mode)
  editxml(x,"//initialization/type", type)
  editxml(x,"//initialization/file", file)

  # Which JavaScript file iLand loads. This is //management/file, NOT
  # //javascript/fileName (which is empty and unused). A bare filename resolves
  # against <system><path><script>, i.e. landscape_alaska_NN/scripts/. The two
  # variants differ only in onYearEnd: the spinup one writes the year-300
  # snapshot and decadal KBDI, the scenario one writes annual KBDI.
  editxml(x, "//management/file", js_file)

  # Landscape-specific KBDIref, replacing the master's generic 0.038. Read from
  # the landscape's own summary so a project file can be regenerated without the
  # combined table existing. Fail rather than fall back: a silent 0.038 would
  # change fire probability across a whole round, and this project has already
  # lost runs to three silent fallbacks (climate resampling, the shadowed
  # snapshot, script 03 skipping missing climate years).
  kbdi_file <- here(landscape_name, "supporting_data", "kbdi_summary",
                    "kbdi_summary.csv")
  if (!file.exists(kbdi_file)) {
    stop("no KBDI summary for '", landscape_name, "' at ", kbdi_file,
         " -- run analysis-scripts/process_kbdi.R first")
  }
  kbdi_tbl <- read.csv(kbdi_file, stringsAsFactors = FALSE)
  if (nrow(kbdi_tbl) != 1 || is.na(kbdi_tbl$kbdi_mean[1])) {
    stop("expected one usable kbdi_mean for '", landscape_name, "', found ",
         nrow(kbdi_tbl), " row(s) in ", kbdi_file)
  }
  # Consume the audit column rather than trusting it: a non-zero value means some
  # cells were zero in only some years, i.e. possibly genuine dry-zero data that
  # process_kbdi.R discarded, which would bias this mean upward.
  if (kbdi_tbl$n_zero_partial[1] > 0) {
    warning(landscape_name, ": n_zero_partial = ", kbdi_tbl$n_zero_partial[1],
            " -- KBDIref may be biased, see the comment in process_kbdi.R")
  }
  # 3 decimals matches how KBDIref is conventionally expressed (the master's
  # 0.038) and is well inside the precision a 66-year estimate supports.
  # Landscapes 04-06 all land on 0.030; their means differ by less than the
  # standard error of any one of them, so that is not a lost distinction.
  # sprintf, not round + as.character: as.character can emit scientific notation
  # for a small value, which iLand would not parse.
  editxml(x, "//modules/fire/KBDIref", sprintf("%.3f", kbdi_tbl$kbdi_mean[1]))

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
# Regenerated 2026-08-19 with four of the six output blocks switched off. The
# 300-year spinup only needs enough state to judge convergence and to hand a
# snapshot to the scenario runs, so tree/sapling/carbon/water were dropped to cut
# output volume and speed the run. filt_cond = 260 still limits the surviving
# outputs to the last 40 years. Re-enable an output here if a spinup diagnostic
# needs it -- the analysis qmds in workflow-output/ read stand and saplingdetail.
for (i in seq_along(landscape_names)) {
  gen_project_file(
    landscape_name     = landscape_names[i],
    master_xml         = master_xml,
    run_type           = "spinup",
    save_tree          = FALSE,
    save_stand         = TRUE,
    save_sapling       = FALSE,
    save_saplingdetail = TRUE,
    save_carbon        = FALSE,
    save_water         = FALSE,
    desired_years      = 1950:1980,
    mod_years          = 300,
    filt_cond          = 260,
    seed               = 1984 + i,
    note               = ""
  )
}

#--------------- Generate future FIRE ONLY xml files for all landscapes ---------------#
# Complete
for (i in seq_along(landscape_names)) {
  gen_project_file(
    landscape_name     = landscape_names[i],
    master_xml         = master_xml,
    run_type           = "scenario",
    save_tree          = FALSE,
    save_stand         = FALSE,
    save_sapling       = FALSE,
    save_saplingdetail = FALSE,
    save_carbon        = FALSE,
    save_water         = FALSE,
    desired_years      = 2015:2100,
    mod_years          = 86,
    filt_cond          = -1,
    seed               = 1984 + i,
    note = "_onlyfire")
}

#--------------- Generate historic FIRE ONLY xml files for all landscapes ---------------#
# Complete
for (i in seq_along(landscape_names)) {
  gen_project_file(
    landscape_name     = landscape_names[i],
    master_xml         = master_xml,
    run_type           = "historic",
    save_tree          = FALSE,
    save_stand         = FALSE,
    save_sapling       = FALSE,
    save_saplingdetail = FALSE,
    save_carbon        = FALSE,
    save_water         = FALSE,
    # Climate coverage is NOT uniform -- audited 2026-08-18 against both the
    # source .nc files and the per-landscape sqlite databases, which agree:
    #
    #   NorEsm2-MM        all 3 ssps, all 6 landscapes   1950-2100  <- only safe choice
    #   TaiESM1 / UKESM   ssp126, landscapes 02-06       1950-2100
    #   TaiESM1 / UKESM   ssp126, landscape 01 (CPCRW)   1980-2100  <- too short
    #   TaiESM1 / UKESM   ssp245 / ssp370, all           1980-2100  <- too short
    #
    # Landscape 01 is the CPCRW landscape, so script 03 takes the CPCRW fallback
    # branch, and the CPCRW downscaling only reaches 1950 for NorEsm2-MM. Hence
    # a 1950-start historic run is NorEsm2-MM only; drop the start to 1980 if all
    # three GCMs are wanted.
    #
    # Also note the 1950-2014 values are NOT shared between the ssp databases of
    # a given GCM (NorEsm2-MM ssp126 vs ssp245 differ by ~0.15 C mean, 0.96 C max
    # in min_temp), even though CMIP6 scenarios branch from a common historical
    # run -- each ssp appears to have been downscaled separately.
    desired_years      = 1950:2015,
    mod_years          = 66,   # inert here: filt_cond = -1 blanks the output
                               # filter and sample_climate is not called. The
                               # real run length is the runner's 4th argument.
    filt_cond          = -1,
    seed               = 1984 + i,
    note = "_onlyfire")
}


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

  # 3. Create scripts/ directory and copy BOTH saveWorkflow variants into it.
  # Both are deployed to every landscape; each project file selects one via
  # //management/file, set per run_type in gen_project_file above. There is no
  # longer a single saveWorkflow.js -- if one turns up in a landscape's scripts/
  # folder it is a stale leftover and no XML references it.
  dir.create(here(lcp, "scripts"), recursive = TRUE, showWarnings = FALSE)
  for (js in c("saveWorkflow_spinup.js", "saveWorkflow_scenario.js")) {
    check_copy(
      file.copy(file.path(shared, js), here(lcp, "scripts", js), overwrite = TRUE),
      paste(lcp, js)
    )
  }
})
