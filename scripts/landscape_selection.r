library(terra)
library(sf)
library(tidyverse)
library(RColorBrewer)

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


#----------------------------------------------------------#
#-------------------- Canada landcover --------------------#

#----- Canada: extract urban locations from 30m landcover --------------------#
# as.points() must allocate all output points at once in C++, so we process
# in 500 km chunks and accumulate incrementally to stay within memory.
lc_path <- paste0("//10.60.2.10/FF_Lab//project_data/na_boreal/",
                  "Landscape building/Landscape selection/GIS Inputs/",
                  "Canada landcover/landcover-2020-classification.tif")
if (!done_already) {
  lc <- rast(lc_path)

  #----- Build 500 km processing chunks in landcover CRS ----------------------#
  temp_eco <- buffer(project(eco, crs(lc)), width = 10000)
  chunks <- as.polygons(
    terra::rast(ext = ext(temp_eco),
                res = c(500000, 500000),
                crs = crs(temp_eco)),
    dissolve = FALSE
  )

  #----- Extract urban cells (class 17) as points, chunk by chunk -------------#
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

  #----- Remove plots within buffer_size km of an urban point -----------------#
  # Buffer is 20 km, plus 22 m for half the diagonal of a 30m grid cell
  urban_ex <- buffer(urban_pts, width = (buffer_size * 1000 + 22))
  in_buf <- sapply(st_intersects(st_as_sf(plots), st_as_sf(urban_ex)),
                   function(x) length(x) == 0)
  plots <- plots[in_buf, ]
}

#----------------------------------------------------------#
#---------------------- Canada roads ----------------------#

if (!done_already) {

  nrn_ns <- vect("Z:/personal_storage/quinn_storage/nrn_rrn_ns_SHAPE/NRN_RRN_NS_SHAPE/NRN_NS_18_0_SHAPE_en/NRN_NS_18_0_ROADSEG.shp")

  roads_gdb <- paste0("//10.60.2.10/FF_Lab//project_data/na_boreal/",
                      "Landscape building/Landscape selection/GIS inputs/",
                      "Canada roads/lrnf000r21f_e/lrnf000r21f_e.gdb")
  sf::st_layers("//10.60.2.10/FF_Lab//project_data/na_boreal/Landscape building/Landscape selection/GIS inputs/Canada roads/lrnf000r21f_e/lrnf000r21f_e.gdb")

  roads <- vect(roads_gdb, layer = "lrnf000r21f_e")
  roads <- project(roads, crs(eco))
# Clip to our region
roads <- terra::intersect(roads, eco)

# Buffer them to 20 km
roads_ex <- buffer(roads, width = (buffer_size * 1000))

p1 <- st_as_sf(plots)
b1 <- st_as_sf(roads_ex)

int <- st_intersects(p1,b1)
# "intersects" returns a list, for each plot, of the ecoregions it intersects
# with. Get all where length is 0 (no intersection)
in_buf <- sapply(int, function(x){length(x) == 0})
plots <- plots[in_buf, ]
}


#----------------------------------------------------------#
#-------------------- Alaska landcover --------------------#

#----- Alaska: extract urban locations from 30m NLCD -------------------------#
lc_path <- normalizePath(
  paste0("//10.60.2.10/FF_Lab//project_data/na_boreal/",
         "Landscape building/Landscape selection/GIS Inputs/",
         "Alaska landcover/NLCD_2016_Land_Cover_AK_20200724/NLCD_2016_Land_Cover_AK_20200724.img"),
  winslash = "/"
)
if (!done_already) {
  lc <- rast(lc_path)

  #----- Build 500 km processing chunks in NLCD CRS ---------------------------#
  chunks <- as.polygons(
    terra::rast(ext = ext(lc),
                res = c(500000, 500000),
                crs = crs(lc)),
    dissolve = FALSE
  )

  #----- Extract urban cells (developed classes) as points, chunk by chunk ----#
  urban_classes <- c("Developed, Open Space",
                     "Developed, Low Intensity",
                     "Developed, Medium Intensity",
                     "Developed, High Intensity")
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
  rm(lc, chunks, temp_eco)
  gc()
  urban_pts <- project(urban_pts, crs(eco))

  #----- Remove plots within buffer_size km of an urban point -----------------#
  # Buffer is 20 km, plus 22 m for half the diagonal of a 30m grid cell
  urban_ex <- buffer(urban_pts, width = (buffer_size * 1000 + 22))
  in_buf <- sapply(st_intersects(st_as_sf(plots), st_as_sf(urban_ex)),
                   function(x) length(x) == 0)
  plots <- plots[in_buf, ]
}


#----------------------------------------------------------#
#---------------------- Alaska Roads ----------------------#

if (!done_already) {
roads <- vect("//10.60.2.10/FF_Lab//project_data/na_boreal/Landscape building/Landscape selection/GIS Inputs/Alaska roads/routes.shp")
roads <- project(roads, crs(eco))

# Clip to our region
roads <- terra::intersect(roads, eco)

# Buffer them to 5 km
roads_ex <- buffer(roads, width = (buffer_size * 1000))

p1 <- st_as_sf(plots)
b1 <- st_as_sf(roads_ex)

int <- st_intersects(p1,b1)
# "intersects" returns a list, for each plot, of the ecoregions it intersects
# with. Get all where length is 0 (no intersection)
in_buf <- sapply(int, function(x){length(x) == 0})
plots <- plots[in_buf,]
  writeVector(plots, "Plots after urban.shp", overwrite=T)
  #wgs_plots <- project(plots, crs("+proj=longlat +datum=WGS84 +no_defs"))
  #writeVector(wgs_plots, "Plots_lat_lon.shp", overwrite=T)
  
} else {
  plots <- vect("Plots after urban.shp")
}

plot(eco, main="After urban filtering", axes=F)
plot(buf, add=T, col="red")
#plot(roads, add=T)
plot(plots, add=T)