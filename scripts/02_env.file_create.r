library(terra)
library(sf)

domain <- st_read("Z:\\\\project_data\\na_boreal\\Landscape building\\Landscape selection\\GIS inputs\\ABoVE_Study_Domain\\ABoVE_Study_Domain.shp")
eco <- st_read("Z:\\\\project_data\\na_boreal\\Landscape building\\Landscape selection\\GIS Inputs\\ecoregions.shp")
landscapes <- st_read("Z:\\\\project_data\\na_boreal\\Landscape building\\Landscape selection\\Selected plots\\final_plots.shp")
plot(domain)
plot(eco)
plot(landscapes)

#soil rasters
clay <- rast("Z://project_data/na_boreal/data_sets/soils/ak/clay_ak.tif")
sand <- rast("Z://project_data/na_boreal/data_sets/soils/ak/sand_ak.tif")
silt <- rast("Z://project_data/na_boreal/data_sets/soils/ak/silt_ak.tif")
depth <- rast("Z://project_data/na_boreal/data_sets/soils/ak/depth_ak.tif")

plot(clay)
plot(sand)
plot(silt)
plot(depth)

tst <- readr::read_delim("C:/Users/asenaq/Documents/GitHub/iLand_automated/gis/env.file.txt")