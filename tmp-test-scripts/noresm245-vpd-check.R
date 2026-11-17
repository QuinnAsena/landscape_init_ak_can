library(RSQLite)
library(DBI)
library(tidyr)
library(dplyr)
library(here)

dirs <- list.dirs(here(), recursive = FALSE)
landscape_names <- basename(dirs[grepl("landscape_", basename(dirs))])
noresm245 <- here(landscape_names, "databases/NorEsm2-MMssp245.sqlite")

check_vpd <- function(input_file) {

  dbconn <- DBI::dbConnect(
    RSQLite::SQLite(),
    dbname = input_file)
  on.exit(DBI::dbDisconnect(dbconn), add = TRUE)

  tabs <- DBI::dbListTables(dbconn)
  message(basename(dirname(dirname(input_file))), ": ", length(tabs), " tables")

  lapply(tabs, function(tb) {
    DBI::dbGetQuery(dbconn, sprintf(
      'select count(*) as n,
              sum(vpd is null) as vpd_na,
              min(year) as yr_min,
              max(year) as yr_max
       from "%s"', tb)) |>
      mutate(tbl = tb, .before = 1)
  }) |>
    bind_rows() |>
    mutate(landscape = basename(dirname(dirname(input_file))), .before = 1)
}

vpd_check <- lapply(noresm245, check_vpd) |> bind_rows()

# summary: one row per landscape
vpd_check |>
  group_by(landscape) |>
  summarise(tables = n(),
            rows   = sum(n),
            vpd_na = sum(vpd_na),
            years  = paste(min(yr_min), max(yr_max), sep = "-"),
            .groups = "drop") |>
  print(n = Inf)

# anything that failed
bad <- filter(vpd_check, vpd_na > 0)
if (nrow(bad) == 0) message("\nno NA vpd anywhere") else print(bad)
