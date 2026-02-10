library(terra)
library(sf)
library(dplyr)
library(ggplot2)

daymetloc<- 'Z:/project_data/jaz/alaska/JFSP/gis/'
daymet_studyarea <- rast(paste0(daymetloc,'ak_noislands_daymetpixels.tif'))

plot(daymet_studyarea)
ak_outline <- as.polygons(daymet_studyarea, dissolve = TRUE) |> st_as_sf()

# Winslow's code from climate step1, same crs as daymet_studyarea
gcm = "NorEsm2-MM"   #"NorEsm2-MM" "TaiESM1"
temp = rast(paste0("Z:/project_data/downscaling/CPCRW/Downscaled ",gcm,"/ssp245/tasmax/",gcm,"-ssp245-tasmax-1950.nc"))
same.crs(temp, daymet_studyarea)

# Arielle's original code:
landscapes_dir <- "Z:/personal_storage/arielle_storage/Files/GIS_Inputs/plot_tiffs"
# Extract the numeric values from the file names
# This code does not seem to extract the file numbers for me.
# Order is important
landscapes_files <- list.files(path = landscapes_dir, pattern = "\\.tif$", full.names = TRUE)
numeric_values <- as.numeric(gsub(".*_(\\d+)\\.tif$", "\\1", basename(landscapes_files)))
# Create an index to order the files
order_index <- order(numeric_values)
# Order the files based on the index
ordered_landscapes_files <- landscapes_files[order_index]

landscapes <- list()
# Loop through the ordered files and load them into separate raster objects
for (i in seq_along(ordered_landscapes_files)) {
  landscapes[[i]] <- rast(ordered_landscapes_files[i])
}
set_crs <- function(raster) {
  crs(raster) <- "ESRI:102001"
  return(raster)
}
# Set the CRS for a list of rasters to "ESRI:102001"
landscapes_albers <- lapply(landscapes[1:5], set_crs)

# my code to check plots
rs_albers <- lapply(landscapes_albers, \(ind) {
  st_as_sf(as.polygons(ext(ind), crs = crs(ind)))
}) |>
bind_rows(.id = "landscape")

ggplot() +
  geom_sf(data = rs_albers, fill = NA, color = "red", linewidth = 0.7) +
  geom_sf(data = ak_outline, fill = NA, color = "black", linewidth = 0.5) +
  coord_sf(expand = FALSE) +
  theme_minimal()

tst <- rast(landscapes_files[1])
crs(tst)
crs(tst) <- "ESRI:102001"
crs(tst)

# This is to show/remember that project(ind, daymet_studyarea) and project(ind, crs(daymet_studyarea)).
# The first one matches match CRS, resolution, extent, and origin / alignment.
# # Initialize a list to store the rasters
# landscapes2 <- list()
# # Loop through the ordered files and load them into separate raster objects
# for (i in seq_along(ordered_landscapes_files)) {
#   ind <- rast(ordered_landscapes_files[i])
#   ind <- project(ind, daymet_studyarea, method = "near")
#   landscapes2[[i]] <- ind
# }

# rs_landscapes2 <- lapply(landscapes2[1:5], \(ind) {
#   st_as_sf(as.polygons(ext(ind), crs = crs(ind)))
# }) |>
# bind_rows(.id = "landscape")

# ggplot() +
#   geom_sf(data = rs_landscapes2, fill = NA, color = "red", linewidth = 0.7) +
#   geom_sf(data = ak_outline, fill = NA, color = "black", linewidth = 0.5) +
#   coord_sf(expand = FALSE) +
#   theme_minimal()

# My code reprojecting to daymet studyarea
landscapes3 <- list()
for (i in seq_along(ordered_landscapes_files)) {
  ind <- rast(ordered_landscapes_files[i])
  ind <- project(ind, crs(daymet_studyarea), res = 100)
  landscapes3[[i]] <- ind
}

rs_landscapes3 <- lapply(landscapes3[1:5], \(ind) {
  st_as_sf(as.polygons(ext(ind), crs = crs(ind)))
}) |>
bind_rows(.id = "landscape")

ggplot() +
  geom_sf(data = rs_landscapes3, fill = NA, color = "red", linewidth = 0.7) +
  geom_sf(data = ak_outline, fill = NA, color = "black", linewidth = 0.5) +
  coord_sf(expand = FALSE) +
  theme_minimal()

# My code using crs("ESRI:102001")
landscapes3 <- list()
for (i in seq_along(ordered_landscapes_files)) {
  ind <- rast(ordered_landscapes_files[i])
  ind <- project(ind, crs("ESRI:102001"), res = 100)
  landscapes3[[i]] <- ind
}

rs_landscapes3 <- lapply(landscapes3[1:5], \(ind) {
  st_as_sf(as.polygons(ext(ind), crs = crs(ind)))
}) |>
bind_rows(.id = "landscape")

ggplot() +
  geom_sf(data = rs_landscapes3, fill = NA, color = "red", linewidth = 0.7) +
  geom_sf(data = ak_outline, fill = NA, color = "black", linewidth = 0.5) +
  coord_sf(expand = FALSE) +
  theme_minimal()


# For checking my saved env.grid files
# Checking locations of my projected env.grid files
env_files <- list.files(path = "C:/Users/asenaq/Documents/GitHub/landscape_init_ak_can", 
                        pattern = "grid.tif$", full.names = TRUE, recursive = TRUE)


rs <- lapply(env_files, \(ind) {
  r <- rast(ind)
  st_as_sf(as.polygons(ext(r), crs = crs(r)))
}) |>
bind_rows(.id = "landscape")

ggplot() +
  geom_sf(data = rs, fill = NA, color = "red", linewidth = 0.7) +
  geom_sf(data = ak_outline, fill = NA, color = "black", linewidth = 0.5) +
  coord_sf(expand = FALSE) +
  theme_minimal()


