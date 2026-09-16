# Run on a Derecho login node:
#   Rscript analysis-scripts/gather_fire_kbdi.R            # every scenario landscape found
#   Rscript analysis-scripts/gather_fire_kbdi.R 01 02      # just these landscapes
#
# For every completed scenario replicate, writes two things NEXT TO area_dom:
#   processed/<treatment>/rep_<N>/fire/fire_table.csv   the `fire` table from that rep's sqlite
#   processed/<treatment>/rep_<N>/kbdi/kbdi.tar.gz      that rep's annual KBDI grids, archived
#
# WHY KBDI IS TARRED RATHER THAN COPIED. A scenario replicate writes one KBDI grid per
# simulated year, so the full set is ~86 files x 780 replicates = ~67,000 small files.
# That many metadata operations on Lustre, from a login node, is slow and antisocial.
# One archive per replicate is 780 operations instead, and far quicker to scp off
# Derecho afterwards. Unpack on the receiving machine with analysis-scripts/unpack_kbdi.R.
#
# COMPLETENESS TEST is the KBDI file count: a replicate that wrote a full set of annual
# grids almost certainly ran to the end. For a scenario run that count is 86, confirmed by
# the user from the Derecho output -- there is no empty year-0 grid.
#
# It is still NOT hard-coded, because the count depends on which workflow wrote the grids.
# saveWorkflow_scenario.js calls saveKBDI() from onYearEnd with no guard, so it writes one
# grid per simulated year (86). saveWorkflow_spinup.js wraps the same function in
# `if (Globals.year % 10 == 0)`, so a 300-year spinup writes only ~31. Hard-coding 86 would
# therefore be wrong the moment this is pointed at spinup output. Instead the script counts
# the grids in every replicate, takes the MODE, processes the replicates that match it, and
# lists any that differ -- the data decides, and an odd replicate is reported rather than
# silently swept in.
#
# Safe to re-run: a replicate whose fire CSV and KBDI archive both already exist is skipped.

library(DBI)
library(RSQLite)

args <- commandArgs(TRUE)
user <- "qasena"
# Same override check_cmdfile_complete.sh uses, so the two agree on where output lives.
root <- Sys.getenv("ILANDC_OUTPUT_ROOT",
                   paste0("/glade/derecho/scratch/", user, "/output_ak_can"))
stopifnot(dir.exists(root))

# ---- 1. find the scenario landscape directories -----------------------------------
landscape_dirs <- list.dirs(root, recursive = FALSE)
landscape_dirs <- grep("_2015-2100scenario$", landscape_dirs, value = TRUE)
if (length(args)) {
  wanted <- paste0("landscape_alaska_", args, "_2015-2100scenario")
  landscape_dirs <- landscape_dirs[basename(landscape_dirs) %in% wanted]
}
if (!length(landscape_dirs)) stop("no scenario landscape directories found under ", root)

# ---- 2. inventory every replicate and count its KBDI grids ------------------------
rows <- list()
for (ld in landscape_dirs) {
  treatments <- basename(list.dirs(ld, recursive = FALSE))
  treatments <- setdiff(treatments, "processed")          # processed/ is our own output
  for (tr in treatments) {
    rep_dirs <- list.dirs(file.path(ld, tr), recursive = FALSE)
    rep_dirs <- rep_dirs[grepl("rep_[0-9]+$", rep_dirs)]
    for (rd in rep_dirs) {
      kbdi_dir <- file.path(rd, "kbdi")
      n_kbdi <- if (dir.exists(kbdi_dir)) length(list.files(kbdi_dir, pattern = "\\.txt$")) else 0L
      rows[[length(rows) + 1L]] <- data.frame(
        landscape = basename(ld), treatment = tr,
        replicate = as.integer(sub(".*rep_", "", rd)),
        rep_dir = rd, n_kbdi = n_kbdi, stringsAsFactors = FALSE
      )
    }
  }
}
if (!length(rows)) stop("no replicate directories found")
inv <- do.call(rbind, rows)

counts <- table(inv$n_kbdi[inv$n_kbdi > 0])
if (!length(counts)) stop("no replicate has any KBDI grids -- nothing to gather")
expected <- as.integer(names(counts)[which.max(counts)])

cat("--- gather_fire_kbdi ---\n")
cat("landscapes:       ", paste(basename(landscape_dirs), collapse = ", "), "\n")
cat("replicates found: ", nrow(inv), "\n")
cat("KBDI grid counts: ", paste(sprintf("%s grids x %d reps", names(counts), as.integer(counts)),
                                collapse = " | "), "\n")
cat("treating", expected, "grids as complete (most common count)\n\n")

odd <- inv[inv$n_kbdi != expected, ]
if (nrow(odd)) {
  cat("SKIPPING", nrow(odd), "replicate(s) whose KBDI count differs:\n")
  for (i in seq_len(nrow(odd))) {
    cat(sprintf("  %-38s %-52s rep %-3d %d grid(s)\n",
                odd$landscape[i], odd$treatment[i], odd$replicate[i], odd$n_kbdi[i]))
  }
  cat("\n")
}

# ---- 3. gather ---------------------------------------------------------------------
todo <- inv[inv$n_kbdi == expected, ]
done <- 0L; skipped <- 0L; failed <- character(0)

for (i in seq_len(nrow(todo))) {
  r  <- todo[i, ]
  ld <- file.path(root, r$landscape)
  out_dir  <- file.path(ld, "processed", r$treatment, paste0("rep_", r$replicate))
  fire_csv <- file.path(out_dir, "fire", "fire_table.csv")
  kbdi_tar <- file.path(out_dir, "kbdi", "kbdi.tar.gz")

  if (file.exists(fire_csv) && file.exists(kbdi_tar)) { skipped <- skipped + 1L; next }

  # fire table -----------------------------------------------------------------
  sqlite <- file.path(r$rep_dir, paste0(r$treatment, "_", r$replicate, ".sqlite"))
  if (!file.exists(sqlite)) { failed <- c(failed, paste("no sqlite:", sqlite)); next }
  db <- DBI::dbConnect(RSQLite::SQLite(), dbname = sqlite)
  ok <- DBI::dbExistsTable(db, "fire")
  if (ok) {
    fire <- DBI::dbReadTable(db, "fire")
    # stamp the identity in, so the CSVs can be row-bound later without losing provenance
    fire$landscape <- r$landscape
    fire$treatment <- r$treatment
    fire$replicate <- r$replicate
    dir.create(dirname(fire_csv), recursive = TRUE, showWarnings = FALSE)
    write.csv(fire, fire_csv, row.names = FALSE)
  }
  DBI::dbDisconnect(db)
  if (!ok) { failed <- c(failed, paste("no fire table:", sqlite)); next }

  # kbdi archive ---------------------------------------------------------------
  # -C so the archive holds bare kbdi_*.txt with no absolute paths; that is what lets
  # unpack_kbdi.R untar it in place on any machine, Windows included.
  dir.create(dirname(kbdi_tar), recursive = TRUE, showWarnings = FALSE)
  rc <- system2("tar", c("-czf", shQuote(kbdi_tar),
                         "-C", shQuote(file.path(r$rep_dir, "kbdi")), "."))
  if (rc != 0) { failed <- c(failed, paste("tar failed:", r$rep_dir)); next }

  done <- done + 1L
  if (done %% 50L == 0L) cat("  ...", done, "replicates gathered\n")
}

cat("\n--- summary ---\n")
cat("gathered:        ", done, "\n")
cat("already present: ", skipped, "\n")
cat("wrong KBDI count:", nrow(odd), "\n")
cat("failed:          ", length(failed), "\n")
if (length(failed)) for (f in failed) cat("  ", f, "\n")
