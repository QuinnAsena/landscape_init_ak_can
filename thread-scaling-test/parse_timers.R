# Parse iLand logs from the thread-scaling benchmark, then answer the two
# questions the benchmark exists for:
#
#   1. Is output writing serial? If `outputs` is flat across thread counts it is a
#      fixed cost per output-year that no packing decision can reduce.
#   2. How does compute scale? (runYear - outputs) against thread count.
#
# Total wall time answers neither on its own, which is why this reads iLand's own
# timer block instead of timing the process.
#
#   Rscript thread-scaling-test/parse_timers.R
#
# Deliberately uses fixed-string matching rather than regex: the timer names
# contain "::" and "()" which are regex metacharacters, and escaping them is how
# this sort of parser usually breaks.

suppressMessages({library(DBI); library(RSQLite)})

args    <- commandArgs(FALSE)
fileArg <- grep("^--file=", args, value = TRUE)
here_dir <- if (length(fileArg)) dirname(sub("^--file=", "", fileArg[1])) else "thread-scaling-test"
results <- file.path(here_dir, "results")
sandbox <- Sys.getenv("ILAND_SANDBOX", "D:/quinn/iland_sandbox/landscape_test")

all_files <- list.files(results, full.names = TRUE)
logs <- all_files[startsWith(basename(all_files), "log_") & endsWith(all_files, ".txt")]
if (!length(logs)) stop("no logs in ", results, " -- run run_thread_scaling.sh first")

# iLand prints durations as "1h 32m 2s", "25m 31.271s", "2171.71ms", "35.581s".
parse_dur <- function(x) {
  if (is.na(x) || !nzchar(x)) return(NA_real_)
  tot <- 0
  for (tk in strsplit(trimws(x), " ", fixed = TRUE)[[1]]) {
    if (!nzchar(tk)) next
    if (endsWith(tk, "ms")) {
      tot <- tot + as.numeric(sub("ms", "", tk, fixed = TRUE)) / 1000
    } else if (endsWith(tk, "h")) {
      tot <- tot + as.numeric(sub("h", "", tk, fixed = TRUE)) * 3600
    } else if (endsWith(tk, "m")) {
      tot <- tot + as.numeric(sub("m", "", tk, fixed = TRUE)) * 60
    } else if (endsWith(tk, "s")) {
      tot <- tot + as.numeric(sub("s", "", tk, fixed = TRUE))
    }
  }
  tot
}

# CAREFUL: iLand emits the same timer names twice in different forms.
#   per year:  19:24:17:484: Timer "ModelController:runYear" : "1463.32ms"
#   summary :  20:56:19:017:       "ModelController:runYear" : "1h 32m 2s"
# Only the summary block at the end holds run totals. Taking the first match
# picks up a single year instead -- exactly the bug this comment exists to stop
# being reintroduced. Drop the per-year lines by their `Timer "` prefix.
timer_of <- function(lines, name) {
  lines <- lines[!grepl('Timer "', lines, fixed = TRUE)]
  key <- paste0(dQuote(name, FALSE), " : ")
  i <- which(grepl(key, lines, fixed = TRUE))
  if (!length(i)) return(NA_real_)
  s    <- lines[i[1]]
  rest <- substring(s, regexpr(key, s, fixed = TRUE) + nchar(key) + 1L)  # past the opening quote
  q    <- regexpr('"', rest, fixed = TRUE)
  parse_dur(if (q > 0) substring(rest, 1, q - 1L) else rest)
}

wanted <- c(runYear      = "ModelController:runYear",
            outputs      = "outputs",
            outputmgr    = "OutputManager::execute()",
            seed_disp    = "seed dispersal",
            establish    = "establishment",
            sapling_grow = "sapling growth",
            grow_trees   = "growTrees()",
            apply_pattern= "applyPattern()",
            water        = "water:run",
            javascript   = "execute javascript")

secs_at <- function(lines, pat) {
  hit <- lines[grepl(pat, lines, fixed = TRUE)]
  if (!length(hit)) return(NA_real_)
  hms <- strsplit(substr(hit[1], 1, 8), ":", fixed = TRUE)[[1]]
  if (length(hms) != 3) return(NA_real_)
  sum(as.numeric(hms) * c(3600, 60, 1))
}

rows <- lapply(logs, function(f) {
  lines <- readLines(f, warn = FALSE)
  tag   <- sub(".txt", "", sub("log_", "", basename(f), fixed = TRUE), fixed = TRUE)
  th    <- suppressWarnings(as.numeric(substring(tag, 2)))
  # model creation: "creating model" -> "running model for"
  t0 <- secs_at(lines, "creating model")
  t1 <- secs_at(lines, "running model for")
  yl <- grep("running model for", lines, fixed = TRUE, value = TRUE)[1]
  yr <- if (is.na(yl)) NA_real_ else
          suppressWarnings(as.numeric(sub(".*running model for ([0-9]+) years.*", "\\1", yl)))
  vals <- vapply(wanted, function(w) timer_of(lines, w), numeric(1))
  c(list(tag = tag,
         # t* threads sweep, n* writers-off sweep, m* memory sweep all vary
         # threadCount. The digits stop at the first underscore, so a suffixed
         # tag like m8_os still reports 8 rather than NA.
         threads  = {
           m <- regmatches(tag, regexpr("^[tnm][0-9]+", tag))
           if (length(m)) as.numeric(substring(m, 2)) else NA_real_
         },
         create_s = if (!is.na(t0) && !is.na(t1)) t1 - t0 else NA_real_,
         years    = yr),
    as.list(vals))
})
d <- do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
d$compute_s <- d$runYear - d$outputs

#--------------- correctness gate: same workload across configs? ---------------#
# NOT an exact-match test, and it cannot be one. iLand parallelises with a
# per-thread RNG stream, so changing the thread count changes which resource unit
# receives which random draws. Bit-identical output across thread counts is
# impossible by design even with randomSeed fixed -- verified 2026-08-24: the
# override IS applied ("result: '42'" in stdout, "set max thread count to N" in
# the log) yet stand row counts still differ by ~0.03%.
#
# What matters is that every config did the same AMOUNT of work. A tolerance test
# on stand rows does that; fire rows do not, because a short run usually has zero
# fires and "all equal at zero" passes while proving nothing.
tol <- 0.02   # 2% -- far below the 20-60% timing differences being interpreted
cat("--- workload check: stand rows across configs (within ", 100 * tol, "%) ---\n", sep = "")
# The sandbox was deleted on 2026-08-25 once the study finished, so the output
# databases the workload check queries are gone. Say so plainly rather than
# quietly reporting NA for every row count -- and point at the archived copy,
# which is the only remaining record of those counts.
sandbox_gone <- !dir.exists(file.path(sandbox, "output"))
if (sandbox_gone) {
  cat("\nNOTE: sandbox output not found at", file.path(sandbox, "output"), "\n")
  cat("  Row counts cannot be recomputed. The measured values are preserved in\n")
  cat("  results/thread_scaling_ARCHIVED.csv -- do not overwrite that file.\n")
  cat("  Rebuild with setup_sandbox.sh and re-run the harness if you need them live.\n")
}

counts <- lapply(d$tag, function(tag) {
  db <- file.path(sandbox, "output", tag, paste0(tag, ".sqlite"))
  if (!file.exists(db)) return(c(stand = NA_real_, fire = NA_real_))
  con <- dbConnect(SQLite(), db, flags = SQLITE_RO); on.exit(dbDisconnect(con))
  have <- dbListTables(con)
  g <- function(t) {
    # the nooutput configs disable the output writers, so these tables are
    # legitimately absent -- guard rather than error
    if (!t %in% have) return(NA_real_)
    n <- dbGetQuery(con, sprintf("select max(rowid) n from `%s`", t))$n
    if (is.na(n)) 0 else as.numeric(n)
  }
  c(stand = g("stand"), fire = g("fire"))
})
d$stand_rows <- vapply(counts, function(x) x[["stand"]], numeric(1))
d$fire_rows  <- vapply(counts, function(x) x[["fire"]],  numeric(1))

# Compare within experiment family, not across: t* (threads sweep), n* (writers
# off), fmt_* (grid format). Configs in different families are meant to differ.
# Family = what the run varies, WITH any tag suffix folded in. Folding the suffix
# in is the point: m8 (5 yr) and m8_y86 (86 yr) must not share a family, or the
# speedup maths compares runs of different lengths. That mistake silently
# corrupted the writers-off result once already.
base <- ifelse(grepl("^t[0-9]", d$tag), "threads",
        ifelse(grepl("^n[0-9]", d$tag), "nooutput",
        ifelse(grepl("^m[0-9]", d$tag), "memthreads",
        ifelse(grepl("^fmt_",   d$tag), "geotiff",
        ifelse(grepl("^c[0-9]+x", d$tag), "concurrency", "other")))))
sfx <- sub("^[tnm][0-9]+", "", d$tag)          # "" or "_os" / "_y86" / ...
sfx[base %in% c("geotiff", "concurrency", "other")] <- ""
d$family <- paste0(base, sfx)
print(d[order(d$family, d$threads, d$tag), c("tag", "family", "stand_rows", "fire_rows")],
      row.names = FALSE)

for (fam in unique(d$family)) {
  sr <- stats::na.omit(d$stand_rows[d$family == fam])
  if (!length(sr)) {
    cat(sprintf("  %-9s no output tables -- workload check not possible\n", fam))
  } else if (length(sr) == 1) {
    cat(sprintf("  %-9s single config, nothing to compare\n", fam))
  } else {
    spread <- diff(range(sr)) / mean(sr)
    cat(sprintf("  %-9s spread %.3f%% -- %s\n", fam, 100 * spread,
                if (spread <= tol) "PASS, same workload" else "FAIL, workloads differ"))
  }
}

#--------------- peak memory ---------------#
# Written per run by poll_memory.ps1 as raw bytes. Absent for runs made before
# the harness was instrumented, so NA rather than an error.
d$peak_gb <- vapply(d$tag, function(tag) {
  f <- file.path(results, paste0("mem_", tag, ".txt"))
  if (!file.exists(f)) return(NA_real_)
  v <- suppressWarnings(as.numeric(readLines(f, warn = FALSE)[1]))
  if (is.na(v) || v <= 0) NA_real_ else v / 1073741824
}, numeric(1))

#--------------- results ---------------#
cat("\n--- timers (seconds), peak_gb = working-set high-water mark ---\n")
print(d[order(d$threads, d$tag), c("tag", "threads", "create_s", "runYear",
                                   "outputs", "compute_s", "outputmgr", "years", "peak_gb")],
      row.names = FALSE)

# Experiment A: memory against thread count, single instance (tags m8, m32)
mt <- d[grepl("^m[0-9]+$", d$tag) & !is.na(d$peak_gb), ]
if (nrow(mt) > 1) {
  mt <- mt[order(mt$threads), ]
  cat("\n--- Experiment A: does thread count change memory? ---\n")
  print(mt[, c("threads", "peak_gb", "runYear", "compute_s")], row.names = FALSE)
  spread <- diff(range(mt$peak_gb)) / mean(mt$peak_gb)
  cat(sprintf("  peak varies %.1f%% across %d-%d threads -- %s\n",
              100 * spread, min(mt$threads), max(mt$threads),
              if (spread < 0.05) "FLAT: memory is landscape state, not threads"
              else "thread count DOES move memory, worth exploiting"))
  yr <- max(mt$years, na.rm = TRUE)
  if (!is.na(yr) && yr >= 80) {
    cat(sprintf("  at %.1f GB each (%d yr), a 235 GB node holds %d instances\n",
                max(mt$peak_gb), yr, floor(235 / max(mt$peak_gb))))
  } else {
    cat(sprintf(paste0("  %.1f GB each, but only %d simulated years -- NOT a basis for",
                       " steps-per-node.\n  Peak memory grows with years (27.0 GB at 1,",
                       " 29.7 at 5, 37.4 at 86). Re-run with YEARS=86.\n"),
                max(mt$peak_gb), yr))
  }
}

# Experiment B: summed peak across N concurrent instances
conc <- list.files(results, pattern = "^mem_conc[0-9]+x[0-9]+\\.txt$")
if (length(conc)) {
  cat("\n--- Experiment B: concurrency against a 235 GB node ---\n")
  for (f in sort(conc)) {
    n <- as.numeric(sub("^mem_conc([0-9]+)x.*$", "\\1", f))
    g <- as.numeric(readLines(file.path(results, f), warn = FALSE)[1]) / 1073741824
    cat(sprintf("  %d instances: %.1f GB summed (%.1f GB each), %s\n", n, g, g / n,
                if (g > 235) sprintf("OVER by %.1f GB", g - 235)
                else sprintf("%.1f GB headroom", 235 - g)))
  }
}

# Scaling is analysed WITHIN a family. Pooling t*, n* and m* would compare runs
# whose output writers differ, which is the whole variable under test.
for (fam in sort(unique(d$family))) {
  sw <- d[d$family == fam & !is.na(d$threads), ]
  if (nrow(sw) < 2) next
  # A family holding two run lengths means a tag collision -- comparing them
  # would produce meaningless speedups, so report rather than compute.
  yrs <- unique(stats::na.omit(sw$years))
  if (length(yrs) > 1) {
    cat(sprintf("\n--- %s: SKIPPED, mixes %s simulated years (tag collision?) ---\n",
                fam, paste(sort(yrs), collapse = "/")))
    print(sw[, c("tag", "threads", "years", "runYear")], row.names = FALSE)
    next
  }
  sw <- sw[order(sw$threads), ]
  b  <- sw[1, ]
  sw$compute_speedup <- b$compute_s / sw$compute_s
  sw$compute_eff     <- sw$compute_speedup / (sw$threads / b$threads)
  sw$outputs_rel     <- sw$outputs / b$outputs
  cat(sprintf("\n--- %s: output cost (outputs_rel near 1.00 = serial) ---\n", fam))
  print(sw[, c("threads", "outputs", "outputs_rel")], row.names = FALSE)
  cat(sprintf("\n--- %s: compute scaling vs %d threads ---\n", fam, b$threads))
  print(sw[, c("threads", "compute_s", "compute_speedup", "compute_eff")], row.names = FALSE)
}

out_csv <- if (sandbox_gone) "thread_scaling_NOCOUNTS.csv" else "thread_scaling.csv"
write.csv(d, file.path(results, out_csv), row.names = FALSE)
cat("\nwritten: ", file.path(results, out_csv), "\n", sep = "")

gb <- sum(vapply(d$tag, function(tag) {
  p <- file.path(sandbox, "output", tag)
  if (!dir.exists(p)) return(0)
  sum(file.size(list.files(p, recursive = TRUE, full.names = TRUE)), na.rm = TRUE)
}, numeric(1))) / 2^30
cat(sprintf("sandbox output holding %.1f GB -- safe to delete once this table is saved\n", gb))
