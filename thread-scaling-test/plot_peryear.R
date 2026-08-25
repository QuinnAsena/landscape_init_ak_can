# Per-year cost curve from a REAL production iLand log.
#
# Why this and not the local runs: the sandbox runs are 5 or 86 years from a
# mature snapshot, so they see a nearly-flat slice of the cost curve. A 300-year
# spinup log starts from bare ground and shows the whole thing, which is what the
# "does per-year cost grow?" question is actually about.
#
# Every phase timer is emitted once per simulated year, so the Nth occurrence of a
# timer is year N. That is the only structure this needs.
#
# usage: Rscript thread-scaling-test/plot_peryear.R [logfile]

here_dir <- {
  fa <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(fa)) dirname(sub("^--file=", "", fa[1])) else "thread-scaling-test"
}
args <- commandArgs(TRUE)
logf <- if (length(args)) args[1] else file.path(here_dir, "derecho_temp_log.txt")
stopifnot(file.exists(logf))

lines <- readLines(logf, warn = FALSE)

# "1m 45.769s", "6658.83ms", "54.059s", "4h 44m 52s" -> seconds
to_sec <- function(x) {
  vapply(x, function(s) {
    if (is.na(s)) return(NA_real_)
    tot <- 0
    for (tk in strsplit(trimws(s), " ")[[1]]) {
      if (!nchar(tk)) next
      if (grepl("ms$", tk))     tot <- tot + as.numeric(sub("ms$", "", tk)) / 1000
      else if (grepl("h$", tk)) tot <- tot + as.numeric(sub("h$", "", tk)) * 3600
      else if (grepl("m$", tk)) tot <- tot + as.numeric(sub("m$", "", tk)) * 60
      else if (grepl("s$", tk)) tot <- tot + as.numeric(sub("s$", "", tk))
    }
    tot
  }, numeric(1), USE.NAMES = FALSE)
}

# Pull every occurrence of a per-year timer, in file order = year order.
# Timer names contain regex metacharacters -- "seed dispersal (all species)" and
# "growTrees()" both have parentheses, which sub() would read as capture groups and
# silently fail to match. So match literally with startsWith and cut by offset.
bare <- sub('^[0-9:]+: ', '', lines)
series <- function(name) {
  pat <- paste0('Timer "', name, '" : "')
  hit <- bare[startsWith(bare, pat)]
  if (!length(hit)) return(numeric(0))
  to_sec(sub('".*$', '', substring(hit, nchar(pat) + 1)))
}

phases <- list(
  total     = "ModelController:runYear",
  seed_disp = "seed dispersal (all species)",
  outputs   = "outputs",
  grow      = "growTrees()",
  pattern   = "applyPattern()"
)
d <- lapply(phases, series)
n <- length(d$total)
cat(sprintf("parsed %d simulated years from %s\n", n, basename(logf)))
d <- lapply(d, function(v) { length(v) <- n; v })
d <- as.data.frame(d)
d$year <- seq_len(n)

# The final year carries the year-300 snapshot (~18 min of `execute javascript`
# inside `outputs`). Keeping it in would compress every other year into the
# bottom of the panel, so it is drawn but flagged.
snap <- which.max(d$total)

png(file.path(here_dir, "results", "per_year_cost.png"),
    width = 1500, height = 1150, res = 132)
par(mfrow = c(2, 1), mar = c(4.2, 4.4, 3.2, 1.2))

ymax <- quantile(d$total, 0.995, na.rm = TRUE)
plot(d$year, d$total, type = "n", ylim = c(0, ymax),
     xlab = "simulated year", ylab = "seconds for that year",
     main = sprintf("Per-year cost grows ~%.0fx over the run (%d years)",
                    mean(tail(d$total[-snap], 20), na.rm = TRUE) /
                    mean(head(d$total, 20), na.rm = TRUE), n))
grid(col = "grey88")
cols <- c(total = "black", seed_disp = "firebrick", outputs = "steelblue",
          grow = "darkgreen", pattern = "darkorange")
for (k in names(cols)) lines(d$year, d[[k]], col = cols[[k]], lwd = if (k == "total") 2.1 else 1.3)
abline(v = d$year[snap], lty = 3, col = "grey45")
text(d$year[snap], ymax * 0.96, "snapshot", pos = 2, cex = 0.72, col = "grey35")
legend("topleft", legend = c("total (runYear)", "seed dispersal", "outputs",
                            "growTrees", "applyPattern"),
       col = cols, lwd = 2, bty = "n", cex = 0.78)

# Share of each year, which is the part that decides whether threads could help:
# seed dispersal is species-parallel (4 species here), so its share is a ceiling
# on what any thread count can address.
sh <- 100 * d$seed_disp / d$total
plot(d$year, sh, type = "l", col = "firebrick", lwd = 2, ylim = c(0, 100),
     xlab = "simulated year", ylab = "% of the year's runtime",
     main = "Seed dispersal share -- the 4-thread-capped phase")
grid(col = "grey88")
lines(d$year, 100 * d$outputs / d$total, col = "steelblue", lwd = 2)
legend("topright", legend = c("seed dispersal (capped at 4 threads)", "outputs (serial)"),
       col = c("firebrick", "steelblue"), lwd = 2, bty = "n", cex = 0.78)
invisible(dev.off())

first20 <- mean(head(d$total, 20), na.rm = TRUE)
last20  <- mean(tail(d$total[-snap], 20), na.rm = TRUE)
cat(sprintf("  year 1-20 mean   : %6.1f s/yr\n", first20))
cat(sprintf("  final 20 mean    : %6.1f s/yr  (%.1fx)\n", last20, last20 / first20))
cat(sprintf("  snapshot year    : %6.1f s (year %d)\n", d$total[snap], d$year[snap]))
cat(sprintf("  seed dispersal   : %5.1f%% of total run\n",
            100 * sum(d$seed_disp, na.rm = TRUE) / sum(d$total, na.rm = TRUE)))
cat(sprintf("  outputs          : %5.1f%% of total run\n",
            100 * sum(d$outputs, na.rm = TRUE) / sum(d$total, na.rm = TRUE)))
write.csv(d, file.path(here_dir, "results", "per_year_cost.csv"), row.names = FALSE)
cat("written: results/per_year_cost.png and per_year_cost.csv\n")
