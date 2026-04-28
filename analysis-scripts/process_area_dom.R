library(dplyr)
library(tidyr)
library(RSQLite)
library(DBI)
library(future.apply)
library(arrow)

args <- commandArgs(TRUE)
user <- args[1]
treatment <- args[2]
replicate <- as.numeric(args[3])


data_path <- paste0("/glade/derecho/scratch/", user, "/output_ak_can/landscape_alaska_01_1950-1980spinup/")

if (length(list.files(data_path)) == 0) {
  stop("No files in data path: ", data_path)
}

input_file <- paste0(data_path, treatment, "/rep_",
                     replicate, "/", treatment, "_",
                     replicate, ".sqlite")

output_dir <- file.path(data_path, "processed", "areaDom", treatment, paste0("rep_", replicate))

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cat(
  "*Processing:* \n\n",
  "treatment: ", treatment, "\n\n",
  "replicate: ", replicate, "\n\n",
  "Input data path: ", data_path, "\n\n",
  "output data path: ", output_dir, "\n\n",
  "current time: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n",
  "input_file: ", input_file, "\n\n"
)

process_chunk <- function(start, end) {

  # end <- start + (span -1)
  # end <- min(start + (span - 1), max_year)


  dbconn <- DBI::dbConnect(
    RSQLite::SQLite(),
    dbname = input_file)

  stand <- tbl(dbconn, "stand") |>
    filter(ru != -1, year %in% start:end) |>
    dplyr::select(year, ru, rid, species, area_ha, count_ha, basal_area_m2) |>
    collect()

# Can include a select() here before collect
  saplingdetail <- tbl(dbconn, "saplingdetail") |>
    filter(year %in% start:end) |>
    select(dbh, n_represented, rid, year, ru, species) |>
    mutate(
      ba = pi * ((dbh / 100) / 2)^2,
      ba_all = ba * n_represented) |>
    group_by(rid, year, ru, species) |>
    summarize(
      count_ha_sap = sum(n_represented),
      dbh_mean_sapling = sum(dbh * n_represented) / sum(n_represented),
      ba_sum_sapling = sum(ba_all)) |>
    collect()

  cat("*Object sizes:* \n\n",
      "saplingdetail: ", format(object.size(saplingdetail), units = "Mb"), "\n\n",
      "stand: ", format(object.size(stand), units = "Mb"), "\n\n")

  stand.t <- full_join(stand, saplingdetail, by = c("rid", "ru", "year", "species")) |>
    mutate(
      across(everything(), \(x) replace(x, is.na(x), 0)),
      count.total.ad.sap = count_ha + count_ha_sap,
      ba.total.ad.sap = basal_area_m2 + ba_sum_sapling) |>
    dplyr::select(
      ru, rid, year, species, area_ha,
      count.total.ad.sap:ba.total.ad.sap
    )


  stand.t.wide <- stand.t |>
    pivot_wider(
      names_from = species,
      values_from = count.total.ad.sap:ba.total.ad.sap,
      values_fill = 0
    )

  rm(stand, saplingdetail, stand.t)
  gc()

  stand.t.wide <- stand.t.wide |>
    mutate(
      total.density.ad.sap =
        count.total.ad.sap_Potr + count.total.ad.sap_Pima +
        count.total.ad.sap_Bene + count.total.ad.sap_Pigl,
      total.ba.ad.sap =
        ba.total.ad.sap_Potr + ba.total.ad.sap_Pima +
        ba.total.ad.sap_Bene + ba.total.ad.sap_Pigl
    )

  stand.t.wide <- stand.t.wide |>
    mutate(
      IV.ad.sap_Pima = case_when(
        total.density.ad.sap != 0 & total.ba.ad.sap != 0 ~
          (count.total.ad.sap_Pima / total.density.ad.sap) +
            (ba.total.ad.sap_Pima / total.ba.ad.sap),
        TRUE ~ 0
      ),
      IV.ad.sap_Pigl = case_when(
        total.density.ad.sap != 0 & total.ba.ad.sap != 0 ~
          (count.total.ad.sap_Pigl / total.density.ad.sap) +
            (ba.total.ad.sap_Pigl / total.ba.ad.sap),
        TRUE ~ 0
      ),
      IV.ad.sap_Potr = case_when(
        total.density.ad.sap != 0 & total.ba.ad.sap != 0 ~
          (count.total.ad.sap_Potr / total.density.ad.sap) +
            (ba.total.ad.sap_Potr / total.ba.ad.sap),
        TRUE ~ 0
      ),
      IV.ad.sap_Bene = case_when(
        total.density.ad.sap != 0 & total.ba.ad.sap != 0 ~
          (count.total.ad.sap_Bene / total.density.ad.sap) +
            (ba.total.ad.sap_Bene / total.ba.ad.sap),
        TRUE ~ 0
      )
    )


  stand.t.wide <- stand.t.wide |>
    mutate(
      sp.dom = as.factor(case_when(
        IV.ad.sap_Pima > 1 ~ "Pima",
        IV.ad.sap_Potr > 1 ~ "Potr",
        IV.ad.sap_Pigl > 1 ~ "Pigl",
        IV.ad.sap_Bene > 1 ~ "Bene",
        IV.ad.sap_Pima < 1 & IV.ad.sap_Pigl < 1 & IV.ad.sap_Potr < 1 &
          IV.ad.sap_Bene < 1 & (IV.ad.sap_Pima + IV.ad.sap_Pigl) > 1
          ~ "Mixed.spruce",
        IV.ad.sap_Pima < 1 & IV.ad.sap_Pigl < 1 & IV.ad.sap_Potr < 1 &
          IV.ad.sap_Bene < 1 & (IV.ad.sap_Bene + IV.ad.sap_Potr) > 1
          ~ "Mixed.deciduous",
        TRUE ~ "Not forested"
      )),
      treatment = treatment,
      replicate = replicate
    )

  cat(
    "*Object sizes:* \n\n",
    "stand.t.wide: ", format(object.size(stand.t.wide), units = "MB"), "\n\n"
  )

  cat(
    "Saving output to: \n",
    file.path(output_dir, paste0("chunk_", start, "_area_dom.parquet")), "\n\n"
  )

  arrow::write_parquet(
    stand.t.wide,
    file.path(output_dir, paste0("chunk_", start, "_area_dom.parquet")),
    use_dictionary = FALSE
  )
  gc()
}

start_time_par <- Sys.time()

# Define range of years
span <- 10
years <- 0:300

year_chunks <- seq(from = min(years), to = max(years), by = span)
chunk_ends <- pmin(year_chunks + span - 1, max(years))
chunks <- data.frame(start = year_chunks, end = chunk_ends)

cat("Processing year chunks: \n")
print(chunks)

# Set up parallel processing (adjust workers as needed)
# REMEMBER TO USE plan(multisession, workers = 4) ON WINDOWS
plan(multicore, workers = 10)
options(future.globals.maxSize = 1 * 1024^3)

future.apply::future_lapply(1:nrow(chunks), function(i) {
  process_chunk(chunks$start[i], chunks$end[i])
})

# Reset future plan to sequential after execution
plan(sequential)

gc()

end_time_par <- Sys.time()

cat(
  "Finished parallel processing in: ", end_time_par - start_time_par, "\n\n",
  "current time: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n"
)
