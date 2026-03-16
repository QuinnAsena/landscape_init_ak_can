library(dplyr)
library(tidyr)
library(purrr)
library(fitdistrplus)
library(terra)
library(here)

# This is a re-write of Winslow's script "generating stands for tree init.Rmd"
in_dir <- here("data", "empirical")
johnstone <- read.table(file.path(in_dir, "Alaska-init-stands-johnstone.txt"), header = TRUE, sep= ",")
walker <- read.table(file.path(in_dir, "Alaska-init-stands-walker.txt"), header = TRUE, sep= "\t")
heights <- read.table(file.path(in_dir, "Johnstone_tree_heights.txt"), header = TRUE, sep = "\t")

# Species keys in the data
# sp = key = num.stands = common name
# bene = pb = 16 = birch
# potr = ta = 25 = aspen
# pima = bs = 66 = black spruce

# I fount the abbreviateions confusing and have converted to species short names

#---------- Proportions and densities ----------#
# Some name matching between datasets
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

# Create a classification based on relative proportions of sp
# johnstone_walker_classified <- johnstone_walker |>
#   mutate(
#     forest_type = case_when(
#       pima.prop >= 0.75 ~ "pima",
#       potr.prop >= 0.75 ~ "potr",
#       bene.prop >= 0.50 ~ "bene",
#       pima.prop >= 0.25 & pima.prop < 0.75 ~ "mixed",
#     #   pima.prop >= 0.25 & pima.prop < 0.75 &
#     #     (potr.prop + bene.prop) >= 0.25 &
#     #     (potr.prop + bene.prop) <= 0.75 ~ "mixed",
#       TRUE ~ NA_character_
#     )
#   )

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


# ***NOTE*** The above code is slightly different from Winslow's original code (below).
# case_when forces exclusivity of the caregories avoiding duplicate classification.
# i.e., when a stand satisfies both conditions for the individual species and mixed class
# Additionally, unclassified species (satisfying no conditions) were silently dropped in the original code.
# I am classifying as mixed for now, resulting in a few (7) more stands in mixed category
# bs = total %>% filter(BS.prop>=0.75)
# ta = total %>% filter(TA.prop>=0.75)
# pb = total %>% filter(PB.prop>=0.50)
# mixed = total %>% filter(BS.prop<=0.75&BS.prop>=0.25&TA.prop+PB.prop<=0.75&TA.prop+PB.prop>=0.25)

#---------- Heights ----------#
# Species naming gets confusing as the use of abbeviated latin name
# is not always consistent with common name (e.g., bene vs birch)
# create a dictionary to link species to their distribution
dist_dict <- tibble(
  species = c("spruce", "aspen", "birch"),
  species_short = c("pima", "potr", "bene"),
  distr   = c("gamma",  "gamma", "weibull"),
  dfunc = c("dgamma", "dgamma", "dweibull")
)
# join the dictionary to the heights data
heights_join <- dist_dict |>
  full_join(heights, by = "species")

# Fit distributions for each species based on the empirical data
params <- heights_join |>
  split(heights_join$species) |>
  purrr::map(\(df) {
    fitdistrplus::fitdist(df$height, df$distr[[1]])
  })

# Plot distributions with fitted curves
# imap() is a special version of map() that iterates over both index/name AND value simultaneously.
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
# # The bug is NOT carried through in W's code.
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

# Take the parameters from the fit distributions and add them to our dictionary
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

# Winslow creates "mixed.sp" with the parameters from the individual species
# remember that species naming is going to get confusing!
# We are going to keep track of short latin name as well as mixed as a grouping variable
dist_dict2 <- dist_dict2 |>
  mutate(species = paste0("mixed.", species),
         species_short = "mixed") |>
  bind_rows(dist_dict2)

# Join the number of stands to the dictionary by forest_type
# This multiplies the mixed category by 3 and assigns each species to a mixed group
dist_dict3 <- johnstone_walker_classified |>
  group_by(forest_type) |> # could be count for shorthand
  summarise(num.stands = n()) |>
  full_join(dist_dict2, by = c("forest_type" = "species_short"))

# My notes from comparing scripts of species, abbreviation and stand number
# Stand number is from original script, only diff is I have 70 mixed stands
# bene = pb = 16 = birch
# potr = ta = 25 = aspen
# pima = bs = 66 = spruce
# mixed = mixed = 63 = mixed.Pima, mixed.Potr, mixed.Bene

# Loop over the dictionary of functions and parameters to create a list
# of all (now 6) categories and generate 20 x number of stands
# This follows the original code by including age 11 and a catch for birch height
set.seed(1984) # set.seed for random draw
sp_heights_dist <- split(dist_dict3, dist_dict3$species) |>
  imap(\(df, nm) {
    args <- list(n = 20 * df$num.stands,
                 shape = df$shape[[1]])
    args[[df$param_name[[1]]]] <- df$param[[1]]

    do.call(df$rfunc[[1]], args) |>
    round(digits = 0) |>
    as.data.frame() |>
      rename(Height = 1) |>
      mutate(
        species = nm,
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

# This is a different way of achieving the original aim of duplicating
# the empirical data 20 times to match the 2 * number of stands above
johnstone_walker_classified_20x <- johnstone_walker_classified |>
  split(johnstone_walker_classified$forest_type) |>
  lapply(\(x) {
    bind_rows(replicate(20, x, simplify = FALSE)) |>
      mutate(id = 1:n())
  })

# Left in my checks for now but can pipe directly to bind_rows and remove:
# johnstone_walker_classified_20x$pima |> arrange(stand_id) |> head(10)
# johnstone_walker_classified_20x$pima |> arrange(stand_id) |> tail(10)
# johnstone_walker_classified_20x$pima |> arrange(id) |> head(10)
# johnstone_walker_classified_20x$pima |> arrange(id) |> tail(10)
# head(sp_heights_dist$spruce)
# tail(sp_heights_dist$spruce)

sp_heights_dist_bind <- bind_rows(sp_heights_dist)
dim(sp_heights_dist_bind)
# sp_heights_dist_bind |> count(species)
# sp_heights_dist_bind |> filter(forest_type == "mixed") |> head(10) |> arrange(id)
johnstone_walker_classified_20x <- bind_rows(johnstone_walker_classified_20x)
dim(johnstone_walker_classified_20x)
# unique(johnstone_walker_classified_20x$forest_type)
# johnstone_walker_classified_20x |>
#   count(forest_type)

# Now that we can join the distribution by _category_ to create the cross-combinations
# between mixed and species using forest_type and id (resulting in mixed.spruce, mixed.aspen...)
stands_final <- sp_heights_dist_bind |>
  full_join(johnstone_walker_classified_20x, by = c("forest_type", "id"))
# Always check dimensions after joining. Running code out-of-order can create a mismatch
nrow(stands_final) == nrow(sp_heights_dist_bind) 

stands_final |>
  count(species)
# By this point all stands have multiplied/duplicated stand_ids by 20 like the original
stands_final|>
  filter(stand_id == 17)
# And all mixed stands have 3 cross-combinations and id does not descriminate sp (same as original)
stands_final|>
  filter(stand_id == 1)
# We have more stands than the original due to the classification code at the beginning
max(stands_final$stand_id)
# HA headstands
head(stands_final)


#---------- Create sapinit dataset ----------#

# this is a little confusing since we still have three density columns per sp
# so we use the stand classification to mpull the correct value
# The we follow Winslow's code for generating count height and age.
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
    height_small = Height / 100,
    height_from = pmax(0.05, height_small - 0.1),
    height_to   = height_from + 0.2
  ) |>
  filter(count != 0) |>
  arrange(id, species)

min(sapinit$height_from)
max(sapinit$height_from)

min(sapinit$height_to)
max(sapinit$height_to)


sapinit |>
  count(species)

sapinit |>
  count(forest_type)

# Add white spruce (Pigl) and give it a stand_id continuation
# The 7800 and 16000 are not from the data but other sources (ask W)
sapinit_pigl <- sapinit |>
  filter(species == "spruce") |>
  mutate(
    count = runif(n(), min = 7800/20, max = 16000/20),
    species = "white_spruce",
    forest_type = "pigl",
    height_from = height_from + 1,
    height_to = height_to + 1,
    age = as.numeric(age) + 15,
    stand_id = stand_id + max(sapinit$stand_id)
  )

# Combine all species and do some janky renaming for iLand.
# iLand is going to reference the stand_id and needs a species to put in the pixel
# mixed.pigl is not a species, by duplicating the stand_id across the 4 mixed categires
# and removing the "mixed." prefix, when that id is called in iLand it may put
# any of the four species in the pixel, and should build a mixed RU.
# Hats off to Winslow, that was real smart but fucking confusing when working through the code.
sapinit_bind <- bind_rows(sapinit, sapinit_pigl) |>
  dplyr::select(stand_id, species, count, height_from, height_to, age, forest_type) |>
  mutate(
    species = as.factor(species),
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
        species == "mixed.birch" ~ "Bene"
      )
  ) |>
  arrange(stand_id)

write.table(
  sapinit_bind,
  file.path(in_dir, "sapinit_bind.txt"),
  row.names = FALSE, col.names = TRUE, sep = ",")

unique(sapinit_bind$forest_type)
# Because of the additional stands in "mixed" we have a stand_id range
# up to 329 rather that 199 (7 more stands * 20)
range(sapinit_bind$stand_id)

# Save onle the necessary columns and in the right order:
sapinit_final <- sapinit_bind |>
  dplyr::select(stand_id, species, count, height_from, height_to, age, forest_type)

write.table(
  sapinit_final,
  file.path(in_dir, "landscape_model_init.txt"),
  row.names = FALSE, col.names = TRUE, sep = ",")


# Now, those stand_ids need to be associated with forest class from step 7
# we are going to have slightly different orders to the original code

# ORIGINAL CODE. NOTE forest class IS UNORDERED
# Pima = 1:66 =  forest class 1
# Potr = 67:91 = forest class 3
# Bene = 92:107 = forest class 4
# mixed = 108:133 = forest class 5
# Pigl = 134:199 = forest class 2


# NEW CODE. NOTE forest class IS UNORDERED
# Bene = 1:16 = forest class type 4
# mixed = 17:86 = forest class type 5
# Pigl = 264:329 = forest class type 2
# Pima = 87:152 =  forest class type 1
# Potr = 153:177 = forest class type 3

# To be safe, lets create dictionary matching indeces to forest class codes made in step 7
sapinit_dict <- sapinit_bind |>
  group_by(forest_type) |>
  summarise(
    min_stand_id = min(stand_id),
    max_stand_id = max(stand_id),
    n = n()
  ) |>
  mutate(
    forest_class = 
      case_when(
        forest_type == "bene" ~ 4,
        forest_type == "mixed" ~ 5,
        forest_type == "pigl" ~ 2,
        forest_type == "pima" ~ 1,
        forest_type == "potr" ~ 3
    ))

write.table(
  sapinit_dict,
  file.path(in_dir, "sapinit_dict.txt"),
  row.names = FALSE, col.names = TRUE, sep = ",")
