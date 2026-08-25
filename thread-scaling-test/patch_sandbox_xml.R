# Fill the sandbox project file's `overwritten_by_csv` placeholders from a real
# scenario CSV row, so the benchmark XML is self-contained.
#
#   Rscript patch_sandbox_xml.R <xml> <csv> <snapshot-relative-path>
#
# Why this exists: the production runner passes these nine settings on the command
# line, one per CSV column, and appends the file extensions. A benchmark harness
# that re-derived them by hand would drift from what the runs actually use -- and
# a missing one fails in a way that is easy to misread. iLand reported
# "Environment: input file does not exist (.../overwritten_by_csv)" and, more
# quietly, ran with epsilon=0 instead of 2.7. Patching from the CSV keeps the
# sandbox honest and the workflow reproducible.
#
# Deliberately mirrors editxml() in scripts/13_project_file_create.r: warn rather
# than fail when an xpath does not resolve to exactly one node, so a silent no-op
# is impossible.

library(xml2)

args <- commandArgs(TRUE)
if (length(args) < 3) stop("usage: patch_sandbox_xml.R <xml> <csv> <snapshot-rel-path>")
xml_path <- args[1]; csv_path <- args[2]; snapshot <- args[3]

editxml <- function(x, tag, value) {
  n <- xml_find_all(x, tag)
  if (length(n) == 1) {
    xml_text(n) <- value
  } else {
    warning("found ", length(n), " nodes for '", tag, "' -- no edit made")
  }
  invisible(NULL)
}

csv <- read.csv(csv_path, stringsAsFactors = FALSE)
csv <- csv[!is.na(csv$gcm) & nzchar(csv$gcm), ]
if (!nrow(csv)) stop("no usable rows in ", csv_path)
r <- csv[1, ]

x <- read_xml(xml_path)

# The extensions are appended by the runner, not stored in the CSV -- that column
# convention is "path without extension".
vals <- list(
  "//system/database/in"             = paste0(r$sp_param, ".sqlite"),
  "//system/database/climate"        = paste0(r$gcm, ".sqlite"),
  "//model/settings/epsilon"         = as.character(r$epsilon),
  "//model/world/environmentFile"    = paste0(r$env_file, ".txt"),
  "//model/world/standGrid/fileName" = paste0(r$stand_grid, ".txt"),
  "//output/saplingdetail/minDbh"    = as.character(r$dbh),
  "//modules/fire/fireReturnInterval"= as.character(r$fri),
  "//modules/fire/onlySimulation"    = tolower(as.character(r$onlysim)),
  # The snapshot is passed explicitly rather than taken from the CSV: the CSV's
  # snapshot_file column is blank for spinups, and the benchmark deliberately
  # starts from a snapshot to get a realistic tree load from year 1.
  "//model/initialization/file"      = paste0(snapshot, ".sqlite")
)
for (k in names(vals)) editxml(x, k, vals[[k]])

write_xml(x, xml_path)

# Report what remains. system.path.output, system.database.out and
# system.logging.logFile are set per run by the harness, so those placeholders
# are expected; anything else is a gap.
left <- xml_find_all(x, "//*[contains(text(),'overwritten')]")
expected <- c("output", "out", "logFile")
cat("patched", length(vals), "settings from", basename(csv_path), "row 1 (", r$gcm, ")\n")
if (length(left)) {
  nm <- xml_name(left)
  cat("placeholders remaining:", paste(nm, collapse = ", "), "\n")
  unexpected <- setdiff(nm, expected)
  if (length(unexpected)) {
    stop("unexpected placeholder(s) left unset: ", paste(unexpected, collapse = ", "))
  }
  cat("  all expected -- these are set per run by run_thread_scaling.sh\n")
}
