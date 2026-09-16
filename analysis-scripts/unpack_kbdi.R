# The other half of gather_fire_kbdi.R. Run it wherever the processed/ tree has been
# copied to -- Cuddles, the laptop, anywhere with R:
#
#   Rscript analysis-scripts/unpack_kbdi.R <root>
#   Rscript analysis-scripts/unpack_kbdi.R //10.60.2.10/FF_Lab/.../output_ak_can
#
# Finds every kbdi.tar.gz anywhere under <root> and unpacks it NEXT TO ITSELF:
#   .../rep_<N>/kbdi/kbdi.tar.gz  ->  .../rep_<N>/kbdi/kbdi_1.txt ... kbdi_86.txt
#
# There are hundreds of these directories, which is exactly why this is a script and not
# something to do by hand. Uses R's own untar() rather than shelling out to tar, so it
# works on Windows as well as Linux.
#
# The archives are LEFT IN PLACE. They are small next to the grids they contain, and
# deleting them would make a re-run impossible if an unpack were interrupted half way.
# Remove them yourself once you are satisfied, e.g. on Linux:
#   find <root> -name kbdi.tar.gz -delete
#
# Safe to re-run: a replicate that already has loose kbdi_*.txt beside its archive is
# skipped, so an interrupted run can simply be started again.

args <- commandArgs(TRUE)
if (!length(args)) stop("usage: Rscript analysis-scripts/unpack_kbdi.R <root>")
root <- args[1]
if (!dir.exists(root)) stop("no such directory: ", root)

archives <- list.files(root, pattern = "^kbdi\\.tar\\.gz$",
                       recursive = TRUE, full.names = TRUE)
if (!length(archives)) stop("no kbdi.tar.gz found under ", root)

cat("--- unpack_kbdi ---\n")
cat("root:     ", root, "\n")
cat("archives: ", length(archives), "\n\n")

done <- 0L; skipped <- 0L; failed <- character(0)

for (tarball in archives) {
  dest <- dirname(tarball)
  if (length(list.files(dest, pattern = "\\.txt$"))) { skipped <- skipped + 1L; next }

  ok <- tryCatch({ utils::untar(tarball, exdir = dest); TRUE },
                 error = function(e) { failed <<- c(failed, paste(tarball, "--", conditionMessage(e))); FALSE },
                 warning = function(w) { failed <<- c(failed, paste(tarball, "--", conditionMessage(w))); FALSE })
  if (!ok) next

  n <- length(list.files(dest, pattern = "\\.txt$"))
  if (n == 0L) { failed <- c(failed, paste("unpacked but no .txt appeared:", tarball)); next }

  done <- done + 1L
  if (done %% 50L == 0L) cat("  ...", done, "archives unpacked\n")
}

cat("\n--- summary ---\n")
cat("unpacked:        ", done, "\n")
cat("already unpacked:", skipped, "\n")
cat("failed:          ", length(failed), "\n")
if (length(failed)) for (f in failed) cat("  ", f, "\n")
