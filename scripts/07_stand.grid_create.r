library(dplyr)
library(tidyr)
library(purrr)
library(fitdistrplus)

johnstone <- read.table("C:/Users/asenaq/Documents/GitHub/landscape_init_ak_can/data/empirical/Alaska-init-stands-johnstone.txt", header = TRUE, sep= ",")
walker <- read.table("C:/Users/asenaq/Documents/GitHub/landscape_init_ak_can/data/empirical/Alaska-init-stands-walker.txt", header = TRUE, sep= "\t")
heights <- read.table("C:/Users/asenaq/Documents/GitHub/landscape_init_ak_can/data/empirical/Johnstone_tree_heights.txt", header = TRUE, sep = "\t")

# bene = pb = 16 = birch
# potr = ta = 25 = aspen
# pima = bs = 66 = black spruce

#---------- Proportions and densities ----------#
johnstone <- johnstone |>
  dplyr::mutate(dataset = "johnstone") |>
  tidyr::unite("Site_name", c("dataset", "site"), sep = "_") |>
  dplyr::select(Site_name, pima.dens = BS.dens, potr.dens = TA.dens, bene.dens = PB.dens, total.dens,
         pima.prop = bs.prop, potr.prop = ta.prop, bene.prop = pb.prop)

walker <- walker |>
  dplyr::mutate(dataset = "walker") |>
  tidyr::unite("Site_name", c("dataset", "burnsite"), sep = "_") |>
  dplyr::select(Site_name, pima.dens = BS.dens.post, potr.dens = TA.dens.post,
         bene.dens = PB.dens.post, total.dens, pima.prop = bs.prop,
         potr.prop = ta.prop, bene.prop = pb.prop)

johnstone_walker <- bind_rows(johnstone, walker) |>
  drop_na(pima.prop)
rownames(johnstone_walker) <- NULL

johnstone_walker_classified <- johnstone_walker |>
  mutate(
    forest_type = case_when(
      pima.prop >= 0.75 ~ "pima",
      potr.prop >= 0.75 ~ "potr",
      bene.prop >= 0.50 ~ "bene",
      pima.prop >= 0.25 & pima.prop < 0.75 ~ "mixed",
    #   pima.prop >= 0.25 & pima.prop < 0.75 &
    #     (potr.prop + bene.prop) >= 0.25 &
    #     (potr.prop + bene.prop) <= 0.75 ~ "mixed",
      TRUE ~ NA_character_
    )
  )

# How about: all else mixed?
johnstone_walker_classified <- johnstone_walker |>
  mutate(
    forest_type = case_when(
      pima.prop >= 0.75 ~ "pima",
      potr.prop >= 0.75 ~ "potr",
      bene.prop >= 0.50 ~ "bene",
      TRUE ~ "mixed"
    )
  ) |>
  arrange(forest_type) |>
  mutate(stand_id = 1:n())

# The above code is slightly different from Winslow's original in that
# case_when forces exclusivity of the caregories (original below).
# The difference is only a few duplicates (6) in "mixed"
# bs = total %>% filter(BS.prop>=0.75)
# ta = total %>% filter(TA.prop>=0.75)
# pb = total %>% filter(PB.prop>=0.50)
# mixed = total %>% filter(BS.prop<=0.75&BS.prop>=0.25&TA.prop+PB.prop<=0.75&TA.prop+PB.prop>=0.25)

#---------- Heights ----------#
# create a dictionary to link species to their distribution
dist_dict <- tibble(
  species = c("spruce", "aspen", "birch"),
  species_short = c("pima", "potr", "bene"),
  distr   = c("gamma",  "gamma", "weibull"),
  dfunc = c("dgamma", "dgamma", "dweibull")
)
# join that to the data
heights_join <- dist_dict |>
  inner_join(heights, by = "species")

# Fit distributions for each species
params <- heights_join |>
  split(heights_join$species) |>
  purrr::map(\(df) {
    fitdistrplus::fitdist(df$height, df$distr[[1]])
  })

# Plot distributions with fitted curves
# imap() is a special version of map()
# that iterates over both index/name AND value simultaneously.
heights_join |>
  split(heights_join$species) |>
  purrr::imap(\(df, sp) {
    d <- density(df$height)
    est <- params[[sp]]$estimate
    d_func <- dist_dict$dfunc[dist_dict$species == sp]

    plot(d, main = sp)
    curve(do.call(d_func, c(list(x = quote(x)), as.list(est))),
          add = TRUE, col = "blue")
  })

# # There is a bug in the original code with specoes==species
# # dplyr evaluates the 'species' column first and returns
# # TRUE for all rows, this is VERY consuing filter behavior.
# # The big is not carried through in W's code.
# estimate_ht_param = function(species,distr){
# heights.y=heights%>%filter(species==species)
# fg=fitdistrplus::fitdist(heights.y$height,distr)
# return(fg)
# }
# # See this example for clarification
# bad_filter <- function(species) {
#   heights |> filter(species == species)
# }
# tail(bad_filter("spruce"))

dist_dict2 <- dist_dict |>
  full_join(
    imap_dfr(params, \(fit, sp) {
      tibble(species = sp,
             shape = fit$estimate[1],
             param = fit$estimate[2],
             param_name = if(fit$distname == "gamma") "rate" else "scale")
    }), by = "species") |>
  mutate(rfunc = case_when(
    dfunc == "dgamma" ~ "rgamma",
    dfunc == "dweibull" ~ "rweibull",
    TRUE ~ NA_character_
  ))

dist_dict2 <- dist_dict2 |>
  mutate(species = paste0("mixed.", species),
         species_short = "mixed") |>
  bind_rows(dist_dict2)

johnstone_walker_count <- johnstone_walker_classified |>
  group_by(forest_type) |>
  summarise(num.stands = n()) |>
  full_join(dist_dict2, by = c("forest_type" = "species_short"))

# bene = pb = 16 = birch
# potr = ta = 25 = aspen
# pima = bs = 66 = spruce
# mixed = mixed = 63 = mixed.Pima, mixed.Potr, mixed.Bene
set.seed(1984)
sp_heights_dist <- split(johnstone_walker_count, johnstone_walker_count$species) |>
  imap(\(df, nm) {
    args <- list(n = 20 * df$num.stands,
                 shape = df$shape[[1]])
    args[[df$param_name[[1]]]] <- df$param[[1]]

    do.call(df$rfunc[[1]], args) |>
    round(digits = 0) |>
    as.data.frame() |>
      rename(Height = 1) |>
      mutate(species = nm,
      Height = ifelse(species == "birch" & Height > 380, 380, Height),
      age = 11,
      id = 1:n(),
      forest_type = case_when(
        species == "spruce" ~ "pima",
        species == "aspen" ~ "potr",
        species == "birch" ~ "bene",
        species %in% c("mixed.spruce", "mixed.aspen", "mixed.birch") ~ "mixed",
        TRUE ~ NA_character_
      ))
})


johnstone_walker_classified_20x <- johnstone_walker_classified |>
  split(johnstone_walker_classified$forest_type) |>
  lapply(\(x) {
#    x <- x |> mutate(stand_id = 1:n())
    bind_rows(replicate(20, x, simplify = FALSE)) |>
      mutate(id = 1:n())
  })

johnstone_walker_classified_20x$pima |> arrange(stand_id) |> head(10)
johnstone_walker_classified_20x$pima |> arrange(stand_id) |> tail(10)
johnstone_walker_classified_20x$pima |> arrange(id) |> head(10)
johnstone_walker_classified_20x$pima |> arrange(id) |> tail(10)
head(sp_heights_dist$spruce)
tail(sp_heights_dist$spruce)

sp_heights_dist_bind <- bind_rows(sp_heights_dist)
sp_heights_dist_bind |> filter(forest_type == "mixed") |> head(10) |> arrange(id)
johnstone_walker_classified_20x <- bind_rows(johnstone_walker_classified_20x)
unique(johnstone_walker_classified_20x$forest_type)

johnstone_walker_classified_20x |>
  count(forest_type)


stands_final <- sp_heights_dist_bind |>
  left_join(johnstone_walker_classified_20x, by = c("forest_type", "id"))

unique(stands_final$forest_type)
stands_final |>
  count(species)

stands_final|>
  filter(stand_id == 17)

max(stands_final$stand_id)

head(stands_final)
tail(stands_final)
head(stands_final |> filter(forest_type == "mixed"))
tail(stands_final |> filter(forest_type == "mixed"))

split(stands_final, stands_final$species) |> 
  lapply(\(x) {
    x |> arrange(id) |> head(10)
})


#---------- Create sapinit dataset ----------#

sapinit <- stands_final |>
  dplyr::select(-c(ends_with("prop"))) |>
  pivot_longer(
    cols = c(pima.dens, potr.dens, bene.dens),
    names_to = "density_type",
    values_to = "density"
  ) |>
  mutate(
    # Match species to their density column
    species_match = case_when(
      species == "spruce" | species == "mixed.spruce" ~ "pima.dens",
      species == "aspen" | species == "mixed.aspen" ~ "potr.dens",
      species == "birch" | species == "mixed.birch" ~ "bene.dens",
      TRUE ~ NA_character_
    ),
    # Keep only matching species-density pairs
    keep = (density_type == species_match)
  ) |>
  filter(keep) |>
  dplyr::select(-c(density_type, species_match, keep)) |>
  mutate(
    count = density / 20,
    height_from = round((Height / 100) - 0.1, digits = 2),
    height_to = round((Height / 100) + 0.1, digits = 2),
    age = as.numeric(age),
    height_from = pmax(height_from, 0.05),
    height_to = ifelse(height_from == 0.05, height_to + 0.05, height_to)
  ) |>
  filter(count != 0) |>
  arrange(stand_id, species)

head(sapinit) |> arrange(id)
tail(sapinit) |> arrange(id)
summary(sapinit)

sapinit |>
  count(species)

sapinit |>
  count(forest_type)

# Optional: Add white spruce (Pigl) variant
sapinit_pigl <- sapinit |>
  filter(species == "spruce") |>
  mutate(
    count = runif(n(), min = 7800/20, max = 16000/20),
    species = "white_spruce",
    forest_type = "pigl",
    height_from = height_from + 1,
    height_to = height_to + 1,
    age = as.numeric(age) + 15
  )

# Combine all species
sapinit_final <- bind_rows(sapinit, sapinit_pigl) |>
  dplyr::select(stand_id, species, count, height_from, height_to, age) |>
  mutate(species = as.factor(species),
         height_from = ifelse(height_from > 4, 3.8, height_from),
         height_to = ifelse(height_to > 4, 4, height_to),
         species = 
          case_when(
            species == "aspen" ~ "Potr",
            species == "birch" ~ "Bene",
            species == "white_spruce" ~ "Pigl",
            species == "spruce" ~ "Pima",
            species == "mixed.spruce" ~ "Pigl",
            species == "mixed.aspen" ~ "Potr",
            species == "mixed.birch" ~ "Bene",
        )) |>
  arrange(species) |>
  mutate(stand_id = row_number()) |>
  ungroup()


sapinit_final |>
  group_by(species) |>
  summarise(
    min_stand_id = min(stand_id),
    max_stand_id = max(stand_id),
    n = n()
  )

sapinit_final |>
  count(species)

write.table(
  sapinit_final,
  "C:/Users/asenaq/Documents/GitHub/landscape_init_ak_can/data/empirical/landscape_model_init.txt",
  row.names = FALSE, col.names = TRUE, sep = ",")























library(terra)
dirs <- normalizePath(list.dirs(full.names = TRUE))
ak_landscape_dirs <- dirs[grepl(".*[\\\\/]landscape_[0-9]+$", dirs)]

landscape_ord <- as.integer(
  sub(".*landscape_([0-9]+).*$", "\\1", ak_landscape_dirs)
)
ord <- order(landscape_ord)
ak_landscape_dirs <- ak_landscape_dirs[ord]

# Temporary single raster for testing
species_init <- terra::rast(list.files(file.path(ak_landscape_dirs, "gis", "init"), full.names = TRUE)[1])

values(species_init) == 1 <- 








library(terra)

dirs <- normalizePath(list.dirs(full.names = TRUE))
ak_landscape_dirs <- dirs[grepl(".*[\\\\/]landscape_[0-9]+$", dirs)]

landscape_ord <- as.integer(
  sub(".*landscape_([0-9]+).*$", "\\1", ak_landscape_dirs)
)
ord <- order(landscape_ord)
ak_landscape_dirs <- ak_landscape_dirs[ord]

#---------- Create stand grid for each landscape ----------#

# Define stand ID ranges for each forest type
stand_ranges <- tibble(
  forest_type = c("pima", "potr", "bene", "mixed", "pigl"),
  min_id = c(1, 67, 92, 108, 134),
  max_id = c(66, 91, 107, 133, 199),
  landscape_code = c(1, 3, 4, 5, 2)  # Code in original forest_species_init raster
)

# Process each landscape
for (landscape_dir in ak_landscape_dirs) {
  
  # Load the forest type raster (values: 1=pima, 2=pigl, 3=potr, 4=bene, 5=mixed, 6=potential)
  forest_type_rast <- terra::rast(
    file.path(landscape_dir, "gis", "init", "forest_species_init.tif")
  )
  
  # Create output raster (copy of forest_type_rast)
  stand_grid <- forest_type_rast
  
  # For each forest type, assign random stand IDs
  for (i in seq_len(nrow(stand_ranges))) {
    type_code <- stand_ranges$landscape_code[i]
    min_id <- stand_ranges$min_id[i]
    max_id <- stand_ranges$max_id[i]
    
    # Create a random stand ID raster for this forest type
    n_pixels <- sum(terra::values(forest_type_rast) == type_code, na.rm = TRUE)
    random_ids <- round(runif(n_pixels, min = min_id, max = max_id + 1), digits = 0)
    
    # Assign random IDs where forest_type matches
    stand_grid <- terra::ifel(
      forest_type_rast == type_code,
      random_ids,
      stand_grid
    )
  }
  
  # Handle potential forest cells (code 6 → 206)
  stand_grid <- terra::ifel(
    forest_type_rast == 6,
    206,
    stand_grid
  )
  
  # Convert potential forest back to 0 (no stand)
  stand_grid <- terra::ifel(
    stand_grid == 206,
    0,
    stand_grid
  )
  
  # Save outputs
  output_dir <- file.path(landscape_dir, "gis", "init")
  
  # GeoTIFF
  terra::writeRaster(
    stand_grid,
    file.path(output_dir, "stand_grid.tif"),
    overwrite = TRUE
  )
  
  # Text file for iLand
  stand_matrix <- as.matrix(stand_grid)
  stand_matrix[is.na(stand_matrix)] <- -9999
  
  write.table(
    stand_matrix,
    file.path(output_dir, "stand_grid.txt"),
    col.names = FALSE,
    row.names = FALSE
  )
  
  cat("Processed:", landscape_dir, "\n")
}

cat("Stand grid creation complete!\n")