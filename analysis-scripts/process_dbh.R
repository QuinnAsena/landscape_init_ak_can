library(dplyr)
library(tidyr)
library(RSQLite)
library(DBI)
library(future.apply)
library(arrow)

landscape <- "landscape_alaska_03_2015-2100scenario"
treatment <- "NorEsm2-MMssp245_dbh2.5_onlysimtrue_yr_1_iLand2.1"
replicate <- 1

user <- "qasena"
data_path <- paste0("/glade/derecho/scratch/", user, "/output_ak_can/", landscape, "/")

output_dir <- file.path(data_path, "processed", treatment, paste0("rep_", replicate), "dbh")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

input_file <- paste0(data_path, treatment, "/rep_",
                     replicate, "/", treatment, "_",
                     replicate, ".sqlite")

dbconn <- DBI::dbConnect(
  RSQLite::SQLite(),
  dbname = input_file)

  saplingdetail <- tbl(dbconn, "saplingdetail") |>
    filter(year == 1) |>
    select(dbh, n_represented, rid, year, ru, species) |>
    group_by(rid, year, ru, species) |>
    summarize(
      dbh_mean_sapling = sum(dbh * n_represented) / sum(n_represented),) |>
    collect()







library(dplyr)
library(tidyr)
library(RSQLite)
library(DBI)
library(future.apply)
library(arrow)

args <- commandArgs(TRUE)
landscape <- args[1]
treatment <- args[2]
replicate <- as.numeric(args[3])

user <- "qasena"
data_path <- paste0("/glade/derecho/scratch/", user, "/output_ak_can/", landscape, "/")

input_file <- paste0(data_path, treatment, "/rep_",
                     replicate, "/", treatment, "_",
                     replicate, ".sqlite")

if (!file.exists(input_file)) stop("Input file not found: ", input_file)

output_dir <- file.path(data_path, "processed", treatment, paste0("rep_", replicate), "dbh")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cat(
  "--- process_dbh ---\n",
  "landscape:  ", landscape, "\n",
  "treatment:  ", treatment, "\n",
  "replicate:  ", replicate, "\n",
  "input_file: ", input_file, "\n",
  "output_dir: ", output_dir, "\n",
  "start time: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n"
)

dbconn <- DBI::dbConnect(
  RSQLite::SQLite(),
  dbname = input_file)

year_range <- tbl(dbconn, "stand") |>
  select(year) |>
  summarise(min_yr = min(year),
            max_yr = max(year)) |>
  collect()
dbDisconnect(dbconn)


process_chunk <- function(start, end) {

  dbconn <- DBI::dbConnect(
    RSQLite::SQLite(),
    dbname = input_file)

  # including dbh weighted mean from original code, but not necessary in this pipeline.
  saplingdetail <- tbl(dbconn, "saplingdetail") |>
    filter(year %in% start:end) |>
    select(dbh, n_represented, rid, year, ru, species) |>
    group_by(rid, year, ru, species) |>
    summarize(
      dbh_mean_sapling = sum(dbh * n_represented) / sum(n_represented),) |>
    collect()

  cat(paste0("[", start, "-", end, "] stand: ", format(object.size(stand), units = "MB"),
             " | saplingdetail: ", format(object.size(saplingdetail), units = "MB"), "\n"))

  dbDisconnect(dbconn)

  cat(paste0("[", start, "-", end, "] stand.t.wide: ", format(object.size(stand.t.wide), units = "MB"), "\n"))
  cat(paste0("[", start, "-", end, "] saving: chunk_", start, "_dbh.parquet\n"))

  arrow::write_parquet(
    stand.t.wide,
    file.path(output_dir, paste0("chunk_", start, "_dbh.parquet")),
    use_dictionary = FALSE
  )
  gc()
}

start_time_par <- Sys.time()

# Define range of years
span <- 10
years <- year_range$min_yr:year_range$max_yr

year_chunks <- seq(from = min(years), to = max(years), by = span)
chunk_ends <- pmin(year_chunks + span - 1, max(years))
chunks <- data.frame(start = year_chunks, end = chunk_ends)

# Set up parallel processing (adjust workers as needed)
# REMEMBER TO USE plan(multisession, workers = 4) ON WINDOWS
if (nrow(chunks) > 10) {
  cpus <- 10
} else {
  cpus <- nrow(chunks)
}

cat("Processing", nrow(chunks), "year chunks with", cpus, "workers:\n")
print(chunks)

plan(multicore, workers = cpus)
options(future.globals.maxSize = 1 * 1024^3)

future.apply::future_lapply(1:nrow(chunks), function(i) {
  process_chunk(chunks$start[i], chunks$end[i])
})

# Reset future plan to sequential after execution
plan(sequential)

gc()

end_time_par <- Sys.time()

cat(
  "\n--- Done ---\n",
  "elapsed:    ", format(end_time_par - start_time_par), "\n",
  "output_dir: ", output_dir, "\n",
  "end time:   ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n"
)
