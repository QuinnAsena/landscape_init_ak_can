# Peak memory against simulated years, and what it means for steps-per-node.
#
# Four measured points, drawn as points and NOT as a fitted curve. The 1->5 year
# slope is 0.675 GB/yr and the 5->86 slope is 0.094 GB/yr -- a 7x deceleration --
# so any line through them would imply precision that does not exist. The reason
# this matters: extrapolating the early slope to 86 years predicts 84 GB against
# the 37.4 GB actually measured, which would have made a 5-year concurrency test
# look reassuring when it was not.
#
# usage: Rscript thread-scaling-test/plot_memory.R

here_dir <- {
  fa <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(fa)) dirname(sub("^--file=", "", fa[1])) else "thread-scaling-test"
}
res <- file.path(here_dir, "results")

peak_gb <- function(tag) {
  f <- file.path(res, paste0("mem_", tag, ".txt"))
  if (!file.exists(f)) return(NA_real_)
  v <- suppressWarnings(as.numeric(readLines(f, warn = FALSE)[1]))
  if (is.na(v) || v <= 0) NA_real_ else v / 1073741824
}

# with-output series (the production configuration), then the writers-off control
on  <- data.frame(years = c(1, 5, 86),
                  gb    = c(peak_gb("m8_y1_probe"), peak_gb("m8"), peak_gb("m8_y86")))
# NB: "n8_y86", not "n8" -- n8 is the 5-year writers-off run from the nooutput
# sweep, and naming it here would put a wrong point on the figure.
off <- data.frame(years = 86, gb = peak_gb("n8_y86"))

if (anyNA(on$gb)) stop("missing a with-output peak: ", paste(on$gb, collapse = ", "))

# A node has 235 GB usable, so this is the per-instance ceiling at N steps/node.
ceil_for <- function(n) 235 / n

png(file.path(res, "memory_growth.png"), width = 1500, height = 700, res = 132)
par(mfrow = c(1, 2), mar = c(4.3, 4.5, 3.4, 1.2))

#--- panel 1: memory against simulated years ---#
ymax <- max(ceil_for(3), on$gb, off$gb, na.rm = TRUE) * 1.10
xlim <- c(0.8, 150)   # padded so the point labels at 1 and 86 are not clipped
plot(on$years, on$gb, type = "n", log = "x", xlim = xlim, ylim = c(0, ymax),
     xlab = "simulated years (log scale)", ylab = "peak working set (GB)",
     main = "Memory grows with years, and it is
model state rather than output")
grid(col = "grey88")

# Per-instance ceilings: a node has 235 GB usable, so N steps means 235/N each.
# Labelled at the right edge to stay clear of the data and the legend.
for (n in c(3, 4, 5)) {
  abline(h = ceil_for(n), lty = 3, col = "grey55")
  text(xlim[2], ceil_for(n), sprintf("%d steps/node", n), pos = 2, offset = 0.2,
       cex = 0.66, col = "grey40")
}

# dashed only to guide the eye between measured points -- explicitly not a fit
lines(on$years, on$gb, lty = 2, col = "grey60")
points(on$years, on$gb, pch = 19, col = "steelblue4", cex = 1.5)
text(on$years, on$gb, sprintf("%.1f", on$gb), pos = c(4, 4, 3), cex = 0.76,
     col = "steelblue4")

if (!is.na(off$gb)) {
  points(off$years, off$gb, pch = 17, col = "firebrick", cex = 1.5)
  text(off$years, off$gb, sprintf("%.1f", off$gb), pos = 1, cex = 0.76, col = "firebrick")
}

legend("bottomright", bty = "n", cex = 0.72, inset = c(0.02, 0.02),
       legend = c("output writers on (production config)",
                  if (!is.na(off$gb)) "output writers OFF" else NULL,
                  "measured points, not a fit"),
       pch = c(19, if (!is.na(off$gb)) 17 else NULL, NA),
       lty = c(NA, if (!is.na(off$gb)) NA else NULL, 2),
       col = c("steelblue4", if (!is.na(off$gb)) "firebrick" else NULL, "grey60"))

#--- panel 2: the deceleration, which is the whole reason short runs mislead ---#
seg   <- sprintf("yr %d-%d", head(on$years, -1), tail(on$years, -1))
slope <- diff(on$gb) / diff(on$years)
bp <- barplot(slope, names.arg = seg, col = c("grey45", "grey72"), border = NA,
              ylab = "marginal growth (GB per simulated year)",
              main = sprintf("Growth decelerates %.0fx,\nso short runs cannot be extrapolated",
                             slope[1] / slope[length(slope)]),
              ylim = c(0, max(slope) * 1.25))
text(bp, slope, sprintf("%.3f", slope), pos = 3, cex = 0.82)
invisible(dev.off())

cat("--- peak memory ---\n")
for (i in seq_len(nrow(on)))
  cat(sprintf("  %3d yr, writers on : %6.2f GB\n", on$years[i], on$gb[i]))
if (!is.na(off$gb)) {
  cat(sprintf("  %3d yr, writers OFF: %6.2f GB\n", off$years, off$gb))
  d_tot <- on$gb[nrow(on)] - on$gb[2]           # 5 -> 86 yr, writers on
  d_out <- on$gb[nrow(on)] - off$gb             # what output accounts for at 86 yr
  cat(sprintf("\n  growth 5->86 yr        : %+.2f GB\n", d_tot))
  cat(sprintf("  of which output buffers: %+.2f GB (%.0f%%)\n", d_out, 100 * d_out / d_tot))
  cat(sprintf("  of which model state   : %+.2f GB (%.0f%%)\n",
              d_tot - d_out, 100 * (d_tot - d_out) / d_tot))
}
cat(sprintf("\n  per-instance ceiling at 4 steps/node: %.1f GB -- measured peak is %.0f%% of it\n",
            ceil_for(4), 100 * on$gb[nrow(on)] / ceil_for(4)))
cat("written: results/memory_growth.png\n")
