# Plot the thread-scaling result.
#   Rscript thread-scaling-test/plot_scaling.R

args <- commandArgs(FALSE)
fa <- grep("^--file=", args, value = TRUE)
here_dir <- if (length(fa)) dirname(sub("^--file=", "", fa[1])) else "thread-scaling-test"
results <- file.path(here_dir, "results")

d <- read.csv(file.path(results, "thread_scaling.csv"))
d <- d[!is.na(d$threads), ]
d <- d[order(d$threads), ]

png(file.path(results, "thread_scaling.png"), width = 1500, height = 700,
    res = 130, type = "cairo")
op <- par(mfrow = c(1, 2), mar = c(4.2, 4.2, 3, 1), mgp = c(2.4, 0.8, 0))

## panel 1: where the time actually goes
ymax <- max(d$runYear) * 1.08
plot(d$threads, d$runYear, type = "b", pch = 16, log = "x", ylim = c(0, ymax),
     xlab = "threads", ylab = "seconds (5 simulated years)",
     main = "Where the time goes", xaxt = "n", lwd = 2)
axis(1, at = d$threads, labels = d$threads)
lines(d$threads, d$outputs,   type = "b", pch = 17, lwd = 2, col = "firebrick")
lines(d$threads, d$compute_s, type = "b", pch = 15, lwd = 2, col = "steelblue")
lines(d$threads, d$seed_disp, type = "b", pch = 18, lwd = 2, col = "darkorange")
abline(h = 0, col = "grey80")
legend("topright", bty = "n", lwd = 2, cex = 0.85,
       pch = c(16, 17, 15, 18),
       col = c("black", "firebrick", "steelblue", "darkorange"),
       legend = c("runYear (total)", "outputs (serial)",
                  "compute (runYear - outputs)", "seed dispersal"))

## panel 2: speedup against the ideal
base <- d[1, ]
sp_total   <- base$runYear   / d$runYear
sp_compute <- base$compute_s / d$compute_s
rel        <- d$threads / base$threads
plot(d$threads, sp_compute, type = "b", pch = 15, log = "x", col = "steelblue",
     ylim = c(0, max(rel)), lwd = 2, xaxt = "n",
     xlab = "threads", ylab = paste0("speedup vs ", base$threads, " threads"),
     main = "Speedup vs linear scaling")
axis(1, at = d$threads, labels = d$threads)
lines(d$threads, rel, lty = 2, col = "grey50", lwd = 2)
lines(d$threads, sp_total, type = "b", pch = 16, lwd = 2, col = "black")
legend("topleft", bty = "n", lwd = 2, cex = 0.85,
       pch = c(NA, 15, 16), lty = c(2, 1, 1),
       col = c("grey50", "steelblue", "black"),
       legend = c("linear (ideal)", "compute", "runYear (total)"))
par(op); dev.off()

cat("written:", file.path(results, "thread_scaling.png"), "\n\n")
out <- data.frame(threads = d$threads,
                  runYear = round(d$runYear, 1),
                  outputs = round(d$outputs, 1),
                  compute = round(d$compute_s, 1),
                  seed_disp = round(d$seed_disp, 1),
                  sp_total = round(sp_total, 2),
                  sp_compute = round(sp_compute, 2),
                  ideal = rel)
print(out, row.names = FALSE)
cat(sprintf("\noutputs: mean %.1f s, spread %.1f%% -- %s\n",
            mean(d$outputs), 100 * diff(range(d$outputs)) / mean(d$outputs),
            if (100 * diff(range(d$outputs)) / mean(d$outputs) < 5)
              "FLAT: serial, thread-independent" else "varies with threads"))
cat(sprintf("seed dispersal: mean %.1f s, spread %.1f%% -- %s\n",
            mean(d$seed_disp), 100 * diff(range(d$seed_disp)) / mean(d$seed_disp),
            if (100 * diff(range(d$seed_disp)) / mean(d$seed_disp) < 5)
              "FLAT: does not scale either" else "scales"))
cat(sprintf("outputs are %.0f%% of total runtime at the best thread count\n",
            100 * d$outputs[which.min(d$runYear)] / min(d$runYear)))
