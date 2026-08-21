# Spot-check the size of each table in an iLand output database WITHOUT reading
# any table into memory. Safe on a Derecho login node against a 300 GB database.
#
# Why not the obvious approach: collect() + object.size() materialises the whole
# table in RAM (a `water` table will not fit) and then reports the R footprint
# rather than bytes on disk. Two SQLite properties avoid both problems:
#
#   1. max(rowid) reads only the rightmost b-tree page -- O(log n), instant even
#      at 466 million rows. It equals the row count for insert-only tables, which
#      iLand outputs are. A table with deleted rows would over-count.
#   2. The payload byte sum is computed inside SQLite over a LIMITed sample, so a
#      single number crosses into R rather than any rows.
#
# Exact page-level accounting would be
#   select name, sum(pgsize) from dbstat group by name
# but RSQLite is not built with SQLITE_ENABLE_DBSTAT_VTAB (checked 2026-08-21,
# RSQLite 2.4.6 -- "no such table: dbstat"). If the sqlite3 CLI is on PATH on
# Derecho it very likely does have it, and then that query, or sqlite3_analyzer,
# beats the estimate below.

library(RSQLite)
library(DBI)

user <- "qasena"

# One or more databases. Listing an old full-output run alongside a new reduced
# one is how to see whether the disabled output blocks explain a size gap.
# Names are labels for the report.
#
# The snapshot deserves the same check -- it is the state every scenario run
# starts from -- but its path shape differs: it is written into the replicate
# directory as spinup_300.sqlite, and only lands in landscape_nn/snapshot/ once
# copied there by hand. A snapshot is a state dump: no table has a `year` column,
# so there is no year range to check -- size_tables() is the useful one. Its
# `snag` and `soil` tables carry exactly one row per simulated resource unit, so
# their ROW COUNT is the RU count (not rows_per_year -- that applies to the
# per-RU-per-year tables carbon/water in the output database) and must not change
# between runs of the same landscape. `trees` and `saplings` are where a
# KBDIref or fire change shows up (landscape_01 went 91.6 M -> 68.4 M trees and
# 88.2 M -> 95.0 M saplings when KBDIref went 0.038 -> 0.029: more fire, fewer
# mature trees, more regeneration).
db_files <- c(
  old = paste0("/glade/derecho/scratch/", user,
               "/output_ak_can/landscape_alaska_03_1950-1980spinup/",
               "NorEsm2-MMssp126_dbh2.5_onlysimfalse_yr_1_iLand2.1/rep_3/",
               "NorEsm2-MMssp126_dbh2.5_onlysimfalse_yr_1_iLand2.1_3.sqlite")
  # ,
  # old_snapshot = paste0("/glade/derecho/scratch/", user,
  #              "/output_ak_can/landscape_alaska_03_1950-1980spinup/",
  #              "NorEsm2-MMssp126_dbh2.5_onlysimfalse_yr_1_iLand2.1/rep_3/",
  #              "spinup_300.sqlite"),
  # collected    = paste0("/glade/work/qasena/landscape_init_ak_can/",
  #              "landscape_alaska_03/snapshot/spinup_300.sqlite")
)

n_sample <- 1000    # rows sampled per table to get bytes/row
exact    <- FALSE   # TRUE = full-scan the payload sum instead of sampling. Still
                    # constant-memory, but reads every page: slow on 300 GB.

#--------------- per-database report ---------------#

size_tables <- function(f, label = basename(f)) {
  if (!file.exists(f)) {
    warning("skipping, file not found: ", f)
    return(invisible(NULL))
  }
  con <- dbConnect(SQLite(), f, flags = SQLITE_RO)   # shared scratch: never write
  on.exit(dbDisconnect(con), add = TRUE)

  file_gb  <- file.size(f) / 2^30
  # as.numeric: pragma returns integers and page_count * page_size overflows
  # R's 32-bit integer above ~2 GB, silently giving NA.
  pages    <- as.numeric(dbGetQuery(con, "pragma page_count")[[1]])
  pagesize <- as.numeric(dbGetQuery(con, "pragma page_size")[[1]])

  cat("\n=== ", label, "\n", sep = "")
  cat("    ", f, "\n", sep = "")
  cat(sprintf("    file %.2f GB   |   %s pages x %s B = %.2f GB\n",
              file_gb, format(pages, big.mark = ","),
              format(pagesize, big.mark = ","), pages * pagesize / 2^30))

  tabs <- dbListTables(con)
  if (!length(tabs)) {
    cat("    (no tables)\n")
    return(invisible(NULL))
  }

  # NB: `tab`, not `tbl` -- the earlier version named the loop variable `tbl`,
  # shadowing dplyr::tbl, so tbl(dbconn, tbl) called a character vector.
  rows <- vapply(tabs, function(tab) {
    as.numeric(dbGetQuery(con, sprintf("select max(rowid) as n from `%s`", tab))$n)
  }, numeric(1))
  rows[is.na(rows)] <- 0

  bytes_per_row <- vapply(tabs, function(tab) {
    flds <- dbListFields(con, tab)
    if (!length(flds)) return(NA_real_)
    # length(cast(x as blob)) is the stored byte width of each value; summed
    # across columns in SQL so only the total is returned.
    expr <- paste(sprintf("length(cast(`%s` as blob))", flds), collapse = " + ")
    src <- if (exact) sprintf("`%s`", tab) else
                      sprintf("(select * from `%s` limit %d)", tab, n_sample)
    q <- dbGetQuery(con, sprintf("select sum(%s) as b, count(*) as k from %s", expr, src))
    if (is.na(q$b) || q$k == 0) NA_real_ else q$b / q$k
  }, numeric(1))

  est_gb <- rows * bytes_per_row / 2^30
  total  <- sum(est_gb, na.rm = TRUE)
  share  <- if (total > 0) est_gb / total else NA_real_

  out <- data.frame(
    table          = tabs,
    rows           = rows,
    bytes_per_row  = round(bytes_per_row, 1),
    est_payload_gb = round(est_gb, 3),
    share_pct      = round(100 * share, 1),
    # Apportioning the true file size by payload share absorbs the bias in
    # length(cast(... as blob)): it returns 8 B for any REAL while SQLite stores
    # small integers in 1-2 B, so the raw estimate runs ~20% high. The relative
    # split is what matters, and this column sums to the actual file size.
    apportioned_gb = round(share * file_gb, 3),
    row.names      = NULL
  )
  out <- out[order(-out$est_payload_gb), ]
  print(out, row.names = FALSE)
  cat(sprintf("    est payload total %.2f GB vs file %.2f GB (ratio %.2f)  [%s]\n",
              total, file_gb, total / file_gb,
              if (exact) "exact" else paste0("sampled n=", n_sample)))
  invisible(out)
}

#--------------- run ---------------#

cat("--- derecho-spotcheck ---\n",
    "databases: ", length(db_files), "\n",
    "mode:      ", if (exact) "exact (full scan)" else paste0("sampled (n=", n_sample, ")"), "\n",
    "start:     ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n", sep = "")

res <- Map(size_tables, db_files, names(db_files))

cat("\ndone: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n", sep = "")

### OUTPUT:
#  cat("--- derecho-spotcheck ---\n",
#      "databases: ", length(db_files), "\n",
#      "mode:      ", if (exact) "exact (full scan)" else paste0("sampled (n=", n_sample, ")"), "\n",
#      "start:     ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n", sep = "")
#  
#  res <- Map(size_tables, db_files, names(db_files))
#  
#  cat("\ndone: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n", sep = "")
#  --- derecho-spotcheck ---
#  databases: 1
#  mode:      sampled (n=1000)
#  start:     2026-08-21 10:26:40
#  
#  === old
#      /glade/derecho/scratch/qasena/output_ak_can/landscape_alaska_03_1950-1980spinup/NorEsm2-MMssp126_dbh2.5_onlysimfalse_yr_1_iLand2.1/rep_3/NorEsm2-MMssp126_dbh2.5_onlysimfalse_yr_1_iLand2.1_3.sqlite
#      file 412.92 GB   |   108,244,746 pages x 4,096 B = 412.92 GB
#           table       rows bytes_per_row est_payload_gb share_pct apportioned_gb
#            tree 2579534174         254.7        611.768      94.6        390.673
#   saplingdetail  501327036          66.5         31.050       4.8         19.828
#           stand    9205194         181.4          1.556       0.2          0.993
#          carbon    2514243         424.7          0.995       0.2          0.635
#         sapling    8470548          96.8          0.764       0.1          0.488
#           water    2514243         203.0          0.475       0.1          0.304
#            fire         21         134.1          0.000       0.0          0.000
#         runinfo          1          76.0          0.000       0.0          0.000
#      est payload total 646.61 GB vs file 412.92 GB (ratio 1.57)  [sampled n=1000]
#  
#  done: 2026-08-21 10:26:40


#--------------- peek at the head of each table ---------------#
#
# Confirms the output filter applied. Script 13 writes the same filter into every
# output block (`year >= filt_cond and year <= mod_years`), so a spinup with
# filt_cond = 260 should start at year 260, not year 1.
#
# `select * from tbl limit n` reads only the first page or two, so it returns in
# about a second even on a 412 GB table, and the first row shows the first year --
# which is the decisive check.
#
# It shows the FIRST year, not the range. That is deliberate. The previous version
# probed evenly spaced rowids to recover the whole range and was withdrawn, because
#     select min(rowid), max(rowid) from tbl
# full-scans the table: SQLite only applies its min/max optimisation when the query
# holds exactly ONE aggregate, so EXPLAIN QUERY PLAN turns from SEARCH into SCAN.
# That is 0.05 s versus 136 s on a 466 M-row table locally, and it never finished
# against a 412 GB table on a Derecho login node. If the last year is ever wanted,
# take max(rowid) in a query of its own and seek that single row.

peek_tables <- function(f, label = basename(f), n = 5) {
  if (!file.exists(f)) {
    warning("skipping, file not found: ", f)
    return(invisible(NULL))
  }
  con <- dbConnect(SQLite(), f, flags = SQLITE_RO)
  on.exit(dbDisconnect(con), add = TRUE)

  cat("\n=== head of each table: ", label, "\n", sep = "")
  for (tab in dbListTables(con)) {
    cat("\n-- ", tab, "\n", sep = "")
    print(dbGetQuery(con, sprintf("select * from `%s` limit %d", tab, n)))
  }
  invisible(NULL)
}

invisible(Map(peek_tables, db_files, names(db_files)))


#--------------- check tree manual ---------------#

library(dplyr)
landscape <- "landscape_alaska_03_1950-1980spinup"
treatment <- "NorEsm2-MMssp126_dbh2.5_onlysimfalse_yr_1_iLand2.1"
replicate <- 3

user <- "qasena"
data_path <- paste0("/glade/derecho/scratch/", user, "/output_ak_can/", landscape, "/")

input_file <- paste0(data_path, treatment, "/rep_",
                     replicate, "/", treatment, "_",
                     replicate, ".sqlite")

dbconn <- DBI::dbConnect(
  RSQLite::SQLite(),
  dbname = input_file)

tree_table <- tbl(dbconn, "tree")
dbDisconnect(dbconn)

#--------------- check spinup Derecho ---------------#

input_file_spinup <- paste0(data_path, treatment, "/rep_",
                     replicate, "/", "spinup_300.sqlite")

dbconn <- DBI::dbConnect(
  RSQLite::SQLite(),
  dbname = input_file_spinup)

DBI::dbListTables(dbconn)
dbDisconnect(dbconn)
#--------------- check spinup Local ---------------#

# Two spinup snapshots of the SAME landscape, compared table by table. The
# snapshot is the state every scenario run starts from, so it is worth checking
# directly rather than inferring from the output database.
#
# What each table tells you:
#   snag, soil   one row per simulated resource unit. These are the CONTROL: same
#                landscape means the same count, so if they move, the landscape
#                geometry changed and nothing else in the comparison is
#                interpretable. For landscape_01 that number is 60,462, which also
#                equals the KBDI-nonzero cell count (60,573 in-footprint cells
#                minus 111 always-zero), so two unrelated measures agree.
#   trees        one row per living tree at year 300. The ecological signal.
#   saplings     one row per sapling cohort. Moves opposite to trees after fire.
#   deadtrees    empty here; iLand only fills it when the deadtree output is on.
#
# The pair below is landscape_01 before and after the KBDIref change: the May run
# used the master default 0.038, the August run the landscape-specific 0.029.
# Lower KBDIref means the actual KBDI is a larger fraction of the reference, so
# more drought, more fire -- expect fewer mature trees and more regeneration.

snap_old <- "landscape_alaska_01/snapshot/spinup_300.sqlite"
snap_new <- paste0("landscape_alaska_01/output/",
                   "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120/rep_1/spinup_300.sqlite")

snapshot_rows <- function(f) {
  con <- dbConnect(SQLite(), f, flags = SQLITE_RO)
  on.exit(dbDisconnect(con), add = TRUE)
  tabs <- dbListTables(con)
  # max(rowid), not count(*): O(log n) instead of a full scan. Valid because
  # iLand only ever inserts.
  vapply(tabs, function(tab) {
    n <- dbGetQuery(con, sprintf("select max(rowid) as n from `%s`", tab))$n
    if (is.na(n)) 0 else as.numeric(n)
  }, numeric(1))
}

compare_snapshots <- function(f_a, f_b, label_a = "old", label_b = "new") {
  for (f in c(f_a, f_b)) {
    if (!file.exists(f)) {
      warning("snapshot not found, skipping comparison: ", f)
      return(invisible(NULL))
    }
  }
  a <- snapshot_rows(f_a)
  b <- snapshot_rows(f_b)

  cat("\n=== snapshot comparison\n")
  cat(sprintf("    %-4s %6.2f GB  %s
", label_a, file.size(f_a) / 2^30, f_a))
  cat(sprintf("    %-4s %6.2f GB  %s
", label_b, file.size(f_b) / 2^30, f_b))

  tabs <- union(names(a), names(b))
  out <- do.call(rbind, lapply(tabs, function(tab) {
    ra <- if (tab %in% names(a)) a[[tab]] else NA_real_
    rb <- if (tab %in% names(b)) b[[tab]] else NA_real_
    data.frame(table = tab, old_rows = ra, new_rows = rb,
               delta = rb - ra,
               pct = if (!is.na(ra) && ra > 0) round(100 * (rb - ra) / ra, 1) else NA_real_)
  }))
  print(out, row.names = FALSE)

  # Trees per resource unit: a density that is directly comparable between runs,
  # using snag as the RU count since it is one row per RU.
  ru_a <- if ("snag" %in% names(a)) a[["snag"]] else NA
  ru_b <- if ("snag" %in% names(b)) b[["snag"]] else NA
  if (!is.na(ru_a) && !is.na(ru_b) && ru_a > 0 && ru_b > 0) {
    cat(sprintf("    RUs (snag rows): %s vs %s%s
",
                format(ru_a, big.mark = ","), format(ru_b, big.mark = ","),
                if (identical(ru_a, ru_b)) "  -- unchanged, comparison is valid"
                else "  -- CHANGED: landscape geometry differs, stop here"))
    cat(sprintf("    trees per RU:    %.0f vs %.0f
",
                a[["trees"]] / ru_a, b[["trees"]] / ru_b))
  }
  invisible(out)
}

compare_snapshots(snap_old, snap_new,
                  label_a = "old", label_b = "new")
