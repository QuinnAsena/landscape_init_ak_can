# This script is based on Lora Murphy's selection process located at:
# Z:\project_data\na_boreal\Landscape building\Landscape selection
# The difference is that I project to the ABoVE study domain in step 1
# instead of using ecoregion as the base crs. This is so that selected
# plots are square and consistent with other ABoVE datasets usedin iLand
# I have adjusted the code for efficiency, the two scripts are conparable
# See Lora's scripts for the full description and evaluation process.

library(terra)
library(sf)
library(tidyverse)
library(here)

# Load the level 3 ecoregions
eco <- vect("//10.60.2.10/FF_Lab//project_data/na_boreal/Landscape building/Landscape selection/GIS inputs/NA_CEC_Eco_Level3")
# Load above study domain as master grid
above_study_domain <- rast("//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/ABoVE_reference_grid_v2_1527/data/ABoVE_Study_Domain.tif")

# Separate out our desired ecoregions
eco3 <- eco[eco$NA_L2NAME %in% c("ALASKA BOREAL INTERIOR", "BOREAL CORDILLERA",
                                 "TAIGA PLAIN")]

# Exclude the taiga shield in Quebec
eco3 <- rbind(eco3,
              eco[eco$NA_L2NAME == "TAIGA SHIELD" &
              eco$NA_L3NAME %in% c("Kazan River and Selwyn Lake Uplands",
                                   "Coppermine River and Tazin Lake Uplands")])
# Combine polygons in a common ecoregion
eco <- aggregate(eco3, by = "NA_L2NAME")
plot(eco, "NA_L2NAME", col = rainbow(4), main = "", axes = FALSE)
rm(eco3)
# THIS IS THE KEY DIFFERENCE FROM ORIGINAL. WE NOW PROJECT TO ABOVE
eco <- project(eco, crs(above_study_domain))
plot(eco, "NA_L2NAME", col = rainbow(4), main = "", axes = FALSE)

plots <- as.polygons(
  terra::rast(ext = ext(eco), res = c(25000, 25000), crs = crs(eco)),
  dissolve = FALSE
)
plots$ID <- 1:length(plots)

#----- Remove any plots that do not appear in the ecoregions -----------------#              
p1 <- st_as_sf(plots)
# Make the ecoregions a single region for this purpose
e1 <- st_as_sf(aggregate(eco))
int <- st_covered_by(p1, e1)
# Intersects returns a list, for each plot, of the ecoregions it intersects
# with. Get all where length is greater than 0 (any intersection)
in_eco <- sapply(int, function(x){length(x) > 0})
plots <- plots[in_eco, ]
rm(p1, e1)

#----- Screen out Canadian provinces other than Yukon and NWT ----------------#
# Load the Canadian provinces
prov <- vect("//10.60.2.10/FF_Lab//project_data/na_boreal/Landscape building/Landscape selection/GIS Inputs/Provinces/lpr_000b16a_e.shp")
prov <- project(prov, crs(plots))

p1 <- st_as_sf(plots)
e1 <- st_as_sf(prov)
int <- st_intersects(p1, e1)
prov_name <- sapply(int,
                    function(x){
                      if (length(x) > 0) {
                        prov$PREABBR[x[1]]
                      } else {"AK"}})
plots <- plots[prov_name %in% c("AK", "N.W.T.", "Y.T.")]

#----- Get the ecoregion designation for each plot ---------------------------#
# If it overlaps 2 regions, we're going to take the first one
p1 <- st_as_sf(plots)
e1 <- st_as_sf(eco)
int <- st_intersects(p1,e1)
eco_name <- sapply(int, function(x){eco$NA_L2NAME[x[1]]})
plots$ecoregion <- eco_name

plot(eco, "NA_L2NAME", col = rainbow(4), main = "", axes = FALSE)
plot(plots, add = T)
rm(p1, e1)
#writeVector(eco, "ecoregions.shp")


#----- Make a shape covering the area 100 km inside our regions --------------#
buf <- buffer(aggregate(eco), width = -(100 * 1000))

p1 <- st_as_sf(plots)
b1 <- st_as_sf(buf)

int <- st_covered_by(p1, b1)
# "covered_by" returns a list, for each plot, of the ecoregions it intersects
# with. Get all where length is greater than 0 (any intersection)
in_buf <- sapply(int, function(x){length(x) > 0})
plots <- plots[in_buf,]

plot(eco, main = "", axes = FALSE)
plot(buf, add = TRUE, col = "red")
plot(plots, add = TRUE)


buffer_size <- 20 # in km
done_already <- FALSE

#----- Urban areas and roads: remove plots within buffer_size km -------------#
if (!done_already) {

  #--- Canada landcover: urban exclusion (class 17) ---------------------------#
  # as.points() must allocate all output points at once in C++, so we process
  # in 500 km chunks and accumulate incrementally to stay within memory.
  lc_path <- paste0("//10.60.2.10/FF_Lab//project_data/na_boreal/",
                    "Landscape building/Landscape selection/GIS Inputs/",
                    "Canada landcover/landcover-2020-classification.tif")
  lc <- rast(lc_path)
  temp_eco <- buffer(project(eco, crs(lc)), width = 10000)
  chunks <- as.polygons(
    terra::rast(ext = ext(temp_eco), res = c(500000, 500000), crs = crs(temp_eco)),
    dissolve = FALSE
  )
  urban_pts <- NULL
  for (i in seq_len(length(chunks))) {
    eco_lc <- crop(lc, chunks[i])
    if (any(!is.na(values(eco_lc)))) {
      lc_pts <- as.points(
        subst(eco_lc, from = 17, to = 1, others = NA), na.rm = TRUE
      )
      if (length(lc_pts) > 0) {
        if (is.null(urban_pts)) urban_pts <- lc_pts
        else urban_pts <- rbind(urban_pts, lc_pts)
      }
    }
    rm(eco_lc)
    gc()
  }
  rm(lc, chunks, temp_eco)
  gc()
  urban_pts <- project(urban_pts, crs(eco))
  urban_ex <- buffer(urban_pts, width = (buffer_size * 1000 + 22))
  in_buf <- sapply(st_intersects(st_as_sf(plots), st_as_sf(urban_ex)),
                   function(x) length(x) == 0)
  plots <- plots[in_buf, ]

  #--- Canada roads ------------------------------------------------------------#
  roads <- vect(paste0("//10.60.2.10/FF_Lab//project_data/na_boreal/",
                       "Landscape building/Landscape selection/",
                       "GIS Inputs/Canada roads/canada_roads.shp"))
  roads <- project(roads, crs(eco))
  roads <- terra::intersect(roads, eco)
  roads_ex <- buffer(roads, width = (buffer_size * 1000))
  in_buf <- sapply(st_intersects(st_as_sf(plots), st_as_sf(roads_ex)),
                   function(x) length(x) == 0)
  plots <- plots[in_buf, ]

  #--- Alaska landcover: urban exclusion (developed classes) ------------------#
  lc_path <- normalizePath(
    paste0("//10.60.2.10/FF_Lab//project_data/na_boreal/",
           "Landscape building/Landscape selection/GIS Inputs/",
           "Alaska landcover/NLCD_2016_Land_Cover_AK_20200724/",
           "NLCD_2016_Land_Cover_AK_20200724.img"),
    winslash = "/"
  )
  lc <- rast(lc_path)
  chunks <- as.polygons(
    terra::rast(ext = ext(lc), res = c(500000, 500000), crs = crs(lc)),
    dissolve = FALSE
  )
  urban_classes <- c("Developed, Open Space", "Developed, Low Intensity",
                     "Developed, Medium Intensity", "Developed, High Intensity")
  urban_pts <- NULL
  for (i in seq_len(length(chunks))) {
    eco_lc <- crop(lc, chunks[i])
    if (any(!is.na(values(eco_lc)))) {
      lc_pts <- as.points(
        subst(eco_lc, from = urban_classes, to = rep(1, 4), others = NA),
        na.rm = TRUE
      )
      if (length(lc_pts) > 0) {
        if (is.null(urban_pts)) urban_pts <- lc_pts
        else urban_pts <- rbind(urban_pts, lc_pts)
      }
    }
    rm(eco_lc)
    gc()
  }
  rm(lc, chunks)
  gc()
  urban_pts <- project(urban_pts, crs(eco))
  urban_ex <- buffer(urban_pts, width = (buffer_size * 1000 + 22))
  in_buf <- sapply(st_intersects(st_as_sf(plots), st_as_sf(urban_ex)),
                   function(x) length(x) == 0)
  plots <- plots[in_buf, ]

  #--- Alaska roads ------------------------------------------------------------#
  roads <- vect(paste0("//10.60.2.10/FF_Lab//project_data/na_boreal/",
                       "Landscape building/Landscape selection/",
                       "GIS Inputs/Alaska roads/routes.shp"))
  roads <- project(roads, crs(eco))
  roads <- terra::intersect(roads, eco)
  roads_ex <- buffer(roads, width = (buffer_size * 1000))
  in_buf <- sapply(st_intersects(st_as_sf(plots), st_as_sf(roads_ex)),
                   function(x) length(x) == 0)
  plots <- plots[in_buf, ]

  writeVector(plots, here("data", "plots_after_urban.shp"), overwrite = TRUE)
} else {
  plots <- vect(here("data", "plots_after_urban.shp"))
}

plot(eco, main = "After urban filtering", axes = FALSE)
plot(buf, add = TRUE, col = "red")
plot(plots, add = TRUE)

tst_plots <- vect(here("data", "lora_proj_temp", "plots_above_proj_lora.shp"))
plot(tst_plots, add = TRUE, col = "green")

#----- ABoVE landcover: mosaic tiles covering the study region ----------------#
if (!done_already) {
  above_lc_files <- list.files(
    "//10.60.2.10/FF_Lab/project_data/na_boreal/data_sets/Annual_Landcover_ABoVE_1691/data",
    pattern = "\\.tif$", full.names = TRUE)
  above_lc_files <- above_lc_files[!grepl("Simplified", above_lc_files)]
  above_lc_vrt <- vrt(above_lc_files, set_names = TRUE)
  mosaic_forest <- crop(above_lc_vrt[[31]], eco)
  writeRaster(mosaic_forest, here("data", "mosaic.tif"), overwrite = TRUE)
} else {
  mosaic_forest <- rast(here("data", "mosaic.tif"))
}

plot(mosaic_forest)
plot(eco, add = TRUE)
plot(plots, add = TRUE, col = "red")


#----- Forest cover: keep plots with >= 75% forested ------------------------#
if (!done_already) {
  # Forest cells = 1, all others = 0; extend to cover full ecoregion extent
  binned_f <- extend(subst(mosaic_forest, from = c(1:4), to = 1, others = 0),
                     ext(eco))
  plots$Propforested <- NA
  for (i in 1:length(plots)) {
    cellm <- crop(binned_f, plots[i])
    vv <- values(cellm)
    plots$Propforested[i] <- sum(vv) / length(vv)
  }
  plots2 <- plots[plots$Propforested >= 0.75 |
                    plots$ecoregion == "TAIGA SHIELD"]
  writeVector(plots2, here("data", "Plots with forest.shp"), overwrite = TRUE)
} else {
  plots2 <- vect(here("data", "Plots with forest.shp"))
}


plot(eco, "NA_L2NAME", col = rainbow(4), main = "Eligible plots", axes = FALSE)
plot(plots2, add = TRUE)

sup_ak <- vect(paste0("//10.60.2.10/FF_Lab//project_data/na_boreal/",
                      "Landscape building/Landscape selection/",
                      "GIS Inputs/AK suppression/fire_management_options.shp"))
sup_ak <- project(sup_ak, crs(plots2))

if (!done_already) {
  int <- st_intersects(st_as_sf(plots2), st_as_sf(sup_ak))
  supp <- sapply(int, function(x) {
    level <- NA
    if      (any(sup_ak$PROT[x] == "C")) level <- "C"
    else if (any(sup_ak$PROT[x] == "F")) level <- "F"
    else if (any(sup_ak$PROT[x] == "M")) level <- "M"
    else if (any(sup_ak$PROT[x] == "L")) level <- "L"
    else if (any(sup_ak$PROT[x] == "U")) level <- "U"
    level
  })
  plots2$Suppression <- supp
  x <- which(is.na(plots2$Suppression) |
               plots2$Suppression %in% c("U", "L", "NA"))
  plots2 <- plots2[x, ]
  writeVector(plots2, here("data", "Eligible plots.shp"), overwrite = TRUE)
} else {
  plots2 <- vect(here("data", "Eligible plots.shp"))
}


# Check out the new eligible plots against those selected using ecoregion
# as the base crs
landscapes_poly <- vect(paste0("//10.60.2.10/FF_Lab/project_data/na_boreal/",
                               "Landscape building/Landscape selection/",
                               "Selected plots/final_plots.shp"))

sup_ak2 <- sup_ak[which(sup_ak$PROT %in% c("C", "F", "M")), ]
plot(sup_ak2, col = "lightgray", main = "AK fire suppression zones", axes = FALSE)
plot(plots2, col = "red", add = TRUE)
plot(landscapes_poly, add = TRUE, col = "black")

plot(plots2)
plot(landscapes_poly, add = TRUE, col = "black")

elig_orig <- vect("//10.60.2.10/FF_Lab/project_data/na_boreal/Landscape building/Landscape selection//Selected Plots/Eligible plots.shp")
plot(eco, "NA_L2NAME", col = rainbow(4), main = "Eligible plots", axes = FALSE)
plot(plots2, col = "blue", add = TRUE)
plot(elig_orig, add = TRUE, col = "black")



# Using nearest matches multiple polygons to a single polygon by distance
# listed arguments currently throw error. terra::nearest not working (atm)
# same.crs(plots2, landscapes_poly)
# crs(landscapes_poly) <- crs(plots2)

# nearest_plots <- terra::nearest(landscapes_poly, plots2)
# nearest_plots <- terra::nearest(landscapes_poly, plots2, k = 5)
# nearest_plots_lines <- nearest(landscapes_poly, plots2, lines = TRUE)

# plot(plots2)
# plot(landscapes_poly, add = TRUE, col = "black")
# plot(nearest_plots, add = TRUE, col = "blue")
# plot(nearest_plots_lines, add = TRUE, col = "pink")


# Full pairwise distance matrix: rows = landscapes_poly, cols = plots2
dist_mat <- as.matrix(terra::distance(landscapes_poly, plots2))

# Greedy unique assignment: sort all pairs by distance and assign the closest
# pair first. If a landscape or plots2 polygon is already matched, skip it.
# This ensures the closer of two competing plots2 polygons keeps its match,
# and the further one falls through to its next nearest landscape polygon.
pairs <- as.data.frame(which(!is.na(dist_mat), arr.ind = TRUE))
pairs$dist <- dist_mat[cbind(pairs$row, pairs$col)]
pairs <- pairs[order(pairs$dist), ]

matched_landscape <- logical(nrow(dist_mat))
matched_plots2    <- logical(ncol(dist_mat))
assignment        <- integer(nrow(dist_mat)) # assignment[i] = index in plots2

for (k in seq_len(nrow(pairs))) {
  i <- pairs$row[k]
  j <- pairs$col[k]
  if (!matched_landscape[i] && !matched_plots2[j]) {
    assignment[i]        <- j
    matched_landscape[i] <- TRUE
    matched_plots2[j]    <- TRUE
  }
  if (all(matched_landscape)) break
}

# assignment[i] gives the plots2 index matched to landscapes_poly[i]
matched <- plots2[assignment, ]

plot(plots2)
plot(landscapes_poly, add = TRUE, col = "black")
plot(matched, add = TRUE, col = "blue")

plot(eco, "NA_L2NAME", col = rainbow(4), main = "Eligible plots", axes = FALSE)
plot(matched, add = TRUE, col = "black")


writeVector(matched, here("data", "final_plots_above_proj.shp"), overwrite = TRUE)








if (!done_already) {
  set.seed(1984)
#----- Random choice for non-taiga shield ecoregions -------------------------#
eco1 <- plots2[plots2$ecoregion == "ALASKA BOREAL INTERIOR"]
final_plots <- eco1[sample(1:length(eco1), 5)]

eco1 <- plots2[plots2$ecoregion == "BOREAL CORDILLERA"]
final_plots <- rbind(final_plots, eco1[sample(1:length(eco1), 5)])

eco1 <- plots2[plots2$ecoregion == "TAIGA PLAIN"]
final_plots <- rbind(final_plots, eco1[sample(1:length(eco1), 5)])

#----- Top 5 forested for taiga shield ---------------------------------------#
eco1 <- plots2[plots2$ecoregion == "TAIGA SHIELD"]
eco1 <- eco1[order(eco1$Propforest, decreasing = T)]
final_plots <- rbind(final_plots, eco1[1:5])
final_plots_lat_lon <- project(final_plots, crs("+proj=longlat +datum=WGS84 +no_defs"))

writeVector(final_plots, "../Selected Plots/final_plots.shp", overwrite=T)
writeVector(final_plots_lat_lon,
            "../Selected Plots/final_plots_lat_lon.shp", overwrite=T)
} else {
  final_plots <- vect("../Selected Plots/final_plots.shp")
  final_plots_lat_lon <- vect("../Selected Plots/final_plots_lat_lon.shp")
}

plot(eco, "NA_L2NAME", col=rainbow(4), main="Final plots", axes=F)
plot(final_plots, add=T)