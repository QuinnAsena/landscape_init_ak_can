library(here)
library(dplyr)

# Tests for 10_stand.grid_process.r outputs.
# Run this script immediately after 10_stand.grid_process.r (objects in
# environment) or standalone (loads from output files).

cat("Loading data...\n")

if (!exists("sapinit_bind")) {
  dirs <- list.dirs(here(), recursive = FALSE)
  landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])
  sapinit_bind <- read.csv(
    here(landscape_names[1], "init", "landscape_model_init.txt"),
    header = TRUE, sep = ",", stringsAsFactors = FALSE)
  cat("  loaded sapinit_bind from file\n")
} else {
  cat("  using sapinit_bind from environment\n")
}

if (!exists("sapinit_dict")) {
  sapinit_dict <- read.csv(
    here("data", "empirical", "sapinit_dict.txt"),
    header = TRUE, sep = ",", stringsAsFactors = FALSE)
  cat("  loaded sapinit_dict from file\n")
} else {
  cat("  using sapinit_dict from environment\n")
}

# ------------------------------------------------------------------ #
pass <- 0
fail <- 0

check <- function(label, expr) {
  result <- tryCatch(expr, error = function(e) FALSE)
  if (isTRUE(result)) {
    cat(sprintf("  PASS  %s\n", label))
    pass <<- pass + 1
  } else {
    cat(sprintf("  FAIL  %s\n", label))
    fail <<- fail + 1
  }
}

# ------------------------------------------------------------------ #
cat("\n--- sapinit_bind: species codes ---\n")

valid_codes <- c("Pima", "Potr", "Bene", "Pigl")
check("all species are valid iLand codes",
  all(sapinit_bind$species %in% valid_codes))

check("no NA species",
  !anyNA(sapinit_bind$species))

# The critical bug check: mixed stands must use Pima, not Pigl
mixed_rows <- sapinit_bind[sapinit_bind$forest_type == "mixed", ]
check("mixed forest_type: conifer component is Pima not Pigl",
  !any(mixed_rows$species == "Pigl"))

check("mixed forest_type: contains only Pima, Potr, Bene",
  all(mixed_rows$species %in% c("Pima", "Potr", "Bene")))

check("pigl forest_type: all rows are Pigl",
  all(sapinit_bind$species[sapinit_bind$forest_type == "pigl"] == "Pigl"))

check("pima forest_type: all rows are Pima",
  all(sapinit_bind$species[sapinit_bind$forest_type == "pima"] == "Pima"))

check("potr forest_type: all rows are Potr",
  all(sapinit_bind$species[sapinit_bind$forest_type == "potr"] == "Potr"))

check("bene forest_type: all rows are Bene",
  all(sapinit_bind$species[sapinit_bind$forest_type == "bene"] == "Bene"))

# ------------------------------------------------------------------ #
cat("\n--- sapinit_bind: height ranges ---\n")

check("height_from >= 0.05 everywhere",
  all(sapinit_bind$height_from >= 0.05))

check("height_to > height_from everywhere",
  all(sapinit_bind$height_to > sapinit_bind$height_from))

check("height_from <= 4.0 (cap threshold)",
  all(sapinit_bind$height_from <= 4.0))

check("height_to <= 4.0 (cap applied)",
  all(sapinit_bind$height_to <= 4.0))

# ------------------------------------------------------------------ #
cat("\n--- sapinit_bind: counts and completeness ---\n")

check("count > 0 everywhere",
  all(sapinit_bind$count > 0))

check("no NA in any column",
  !anyNA(sapinit_bind))

check("all five forest types present",
  all(c("bene", "mixed", "pigl", "pima", "potr") %in% sapinit_bind$forest_type))

# ------------------------------------------------------------------ #
cat("\n--- sapinit_bind: stand ID structure ---\n")

# Stand ID ranges for each forest type must not overlap
ranges <- sapinit_bind |>
  group_by(forest_type) |>
  summarise(lo = min(stand_id), hi = max(stand_id), .groups = "drop") |>
  arrange(lo)

overlapping <- any(sapply(seq_len(nrow(ranges) - 1), function(i) {
  ranges$hi[i] >= ranges$lo[i + 1]
}))
check("stand_id ranges do not overlap between forest types",
  !overlapping)

pigl_min  <- min(sapinit_bind$stand_id[sapinit_bind$forest_type == "pigl"])
nonpigl_max <- max(sapinit_bind$stand_id[sapinit_bind$forest_type != "pigl"])
check("pigl stand IDs are strictly above all non-pigl stand IDs",
  pigl_min > nonpigl_max)

# Each mixed stand_id should appear exactly 3 times (Pima, Potr, Bene)
mixed_counts <- mixed_rows |> count(stand_id)
check("every mixed stand_id has exactly 3 species rows",
  all(mixed_counts$n == 3))

# ------------------------------------------------------------------ #
cat("\n--- sapinit_dict: structure and correctness ---\n")

check("all five forest types in dict",
  all(c("bene", "mixed", "pigl", "pima", "potr") %in% sapinit_dict$forest_type))

expected_classes <- c(bene = 4, mixed = 5, pigl = 2, pima = 1, potr = 3)
actual_classes   <- setNames(sapinit_dict$forest_class, sapinit_dict$forest_type)
check("forest class codes are correct (bene=4, mixed=5, pigl=2, pima=1, potr=3)",
  all(actual_classes[names(expected_classes)] == expected_classes))

# dict min/max should match what is actually in sapinit_bind
true_ranges <- sapinit_bind |>
  group_by(forest_type) |>
  summarise(true_min = min(stand_id), true_max = max(stand_id), .groups = "drop")
dict_check <- left_join(sapinit_dict, true_ranges, by = "forest_type")
check("dict min_stand_id matches sapinit_bind",
  all(dict_check$min_stand_id == dict_check$true_min))
check("dict max_stand_id matches sapinit_bind",
  all(dict_check$max_stand_id == dict_check$true_max))

check("no NA in sapinit_dict",
  !anyNA(sapinit_dict))

# ------------------------------------------------------------------ #
cat(sprintf("\n%d passed, %d failed\n", pass, fail))
if (fail > 0) stop(sprintf("%d test(s) failed — see output above", fail))
