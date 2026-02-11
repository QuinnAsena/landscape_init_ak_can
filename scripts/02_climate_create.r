library(terra)
library(sf)
library(tidyr)
library(dplyr)
library(lubridate)

# Load one layer of the whole of Alaska as a template to crop landcapes
ak_climate <- rast(
  "Z:/project_data/downscaling/Alaska/Downscaled CMIP6 NorESM2-MM/ssp126/tasmax/CMIP6 NorESM2-MM-ssp126-tasmax-2015.nc",
  lyrs = 4)
# plot(ak_climate)

# Load env.grid files (careful of crs here, they are in ESRI:102001)
env_files <- list.files(path = "C:/Users/asenaq/Documents/GitHub/landscape_init_ak_can", 
                        pattern = "grid.tif$", full.names = TRUE, recursive = TRUE)
landscape_names <- sub(".*(landscape_[0-9]+).*", "\\1", env_files)

# Aggregate the env.grid to match 1000x1000 of climtae data
env_grids_coarse <- lapply(env_files, \(ind) {
  rast(ind) |> aggregate(fact = 10)
})
names(env_grids_coarse) <- landscape_names

# Convert env.grid to points for extraction
env_grids_sp <- lapply(env_files, \(ind) {
  r <- rast(ind)
  r <- as.points(r, values = TRUE)
  names(r) <- "env.gridCell"
  r
})
names(env_grids_sp) <- landscape_names

# reproject climate to env.grid (matches resolution and extent)
ak_climate_proj <- Map(\(tmpl, nm) {
  out <- file.path(nm, "climate")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  r <- project(ak_climate, tmpl, method = "near")
  values(r) <- seq_len(ncell(r))
  names(r)  <- "climate.gridCell"
  writeRaster(r, file.path(out, "climate.grid.tif"),
              overwrite = TRUE)
  r
}, env_grids_coarse, names(env_grids_coarse))


# convert projected climate to points for later
ak_climate_sp <- Map(\(idx, nm) {
  out <- file.path(nm, "climate")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  clim_vec <- as.points(idx, values = TRUE)
  writeVector(clim_vec, file.path(out, "climate_cells_extract.shp"),
              overwrite = TRUE)
  clim_vec
}, ak_climate_proj, names(ak_climate_proj))

# Extract values from projected climate at env.grid points
# env.grid RUs now align with climate gridcells
rasValue <- Map(\(r, p, nm) {
  out <- file.path(nm, "climate")
  env_clim_link <- terra::extract(r, p, df = TRUE, bind = TRUE)
  write.table(env_clim_link, file.path(out, "env.grid to climate.grid link.txt"),
              row.names = FALSE)
  env_clim_link
}, ak_climate_proj, env_grids_sp, names(ak_climate_proj))

lapply(rasValue, head, 20)
lapply(rasValue, tail, 20)

# Different NorESM timespan? 1980 vs 1950?

process_climate <- function(gcm, ssp, var, year, ak_climate_sp_files, ak_climate_tif_files, in_dir) {
  out_dir <- file.path(in_dir, gcm, ssp, var)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  ak_clim_in <- file.path("Z:/project_data/downscaling/Alaska", paste0("Downscaled CMIP6 ", gcm), ssp, var, paste0("CMIP6 ", gcm, "-", ssp, "-", var, "-", year, ".nc"))

  ak_climate_var <- rast(ak_clim_in)
  ak_climate_sp <- vect(ak_climate_sp_files)
  ak_climate_proj <- rast(ak_climate_tif_files)

  ak_climate_var_proj <- project(ak_climate_var, ak_climate_proj, method="bilinear")
  rm(ak_climate_var); gc()

  if (all(grepl("rsds", names(ak_climate_var_proj)))) {
    ak_climate_var_proj <- (ak_climate_var_proj * 86400) / 1000000
  }

  if (all(grepl("vp", names(ak_climate_var_proj)))) {
    vp_names <- paste0("vp_", seq_len(nlyr(ak_climate_var_proj)))
    if (!identical(names(ak_climate_var_proj), vp_names)) {
      names(ak_climate_var_proj) <- vp_names
    }
  }

  ak_climate_var_df <- as.data.frame(terra::extract(ak_climate_var_proj, ak_climate_sp, bind = TRUE))
  names(ak_climate_var_df)[1] <- "climate.gridCell" # shape files have a 10 chr limit in field names. maybe gpkg is a workaround?

  ak_climate_var_df <- ak_climate_var_df |>
    tidyr::pivot_longer(
      cols = -climate.gridCell,
      names_to = "y_day",
      values_to = "value") |>
    dplyr::mutate(
      y_day = as.numeric(sub("vp_", "", y_day)),
      day_of_year = ifelse(lubridate::leap_year(year) & y_day >= 60, y_day + 1, y_day),
      date = lubridate::make_date(year) + lubridate::days(day_of_year - 1),
      value = round(value, 3)) |>
    dplyr::select(climate.gridCell, value, date)
  write.table(ak_climate_var_df, file.path(out_dir, paste0(gcm, "-", ssp, "-", var, "-", year, ".txt")), row.names = FALSE, sep = "\t")
}

 paste0(gcm, "-", ssp, "-", var, "-", "year", ".txt")

gcm <- "NorEsm2-MM"
ssp <- "ssp126"
var <- "vp"
year <- 2015


dirs <- normalizePath(list.dirs(full.names = TRUE))
ak_climate_dirs <- dirs[grepl(".*[\\\\/]landscape_[0-9]+[\\\\/]climate.*", dirs)]
ak_climate_sp_files <- list.files(
  ak_climate_dirs, full.names = TRUE, pattern = "\\.shp$"
)

ak_climate_tif_files <- list.files(
  ak_climate_dirs, full.names = TRUE, pattern = "\\.tif$"
)


process_climate(
  gcm = gcm,
  ssp = ssp,
  var = "vp",
  year = year,
  ak_climate_sp_files = ak_climate_sp_files[1],
  ak_climate_tif_files = ak_climate_tif_files[1],
  in_dir = ak_climate_dirs[1])



gcm <- "NorEsm2-MM"
model <- gcm
ssp <- "ssp126"
var <- "vp"
year <- 1950






climate.grid.repr <- ak_climate_proj[[1]]

ignore_leap_years <- function(year, day_of_year) {
  # Check if the year is a leap year
  if (leap_year(year) && day_of_year > 59) {
    # Add 1 to skip the leap day (February 29)
    day_of_year <- day_of_year + 1
  }
return(day_of_year)
  }
ncol <- function(x) dim(x)[2]

process.climate = function(model,ssp,var){
r=rast(file.path("Z:/project_data/downscaling/Alaska", paste0("Downscaled CMIP6 ", gcm), ssp, var, paste0("CMIP6 ", gcm, "-", ssp, "-", var, "-", year, ".nc")))
plot(r[[1]])
r.repr=project(r,climate.grid.repr, method="bilinear")
plot(r.repr[[1]])
if(var=="rsds"){
  r.repr = (r.repr * 86400)/1000000  #Convert radiation from watts/m2 to megajoules m2 day-1 (day length/1000000 joules per megajoule)
}else{
  r.repr=r.repr
}

t=as.data.frame(terra::extract(r.repr,climate.grid.sp,bind=T))
names(t)[1] <- "climate.gridCell"
n=ncol(t)
t_long <- tidyr::gather(t, y_day,value , 2:n)
if(var=="vp" &year<1980){
  t_long <- t_long %>% separate(y_day, c('vp', 'y_day'), sep = "\\.") # Had to add this given the name in vapor pressure changed
}else{
t_long <- t_long %>% separate(y_day, c('vp', 'y_day'), sep = '_')
}
t_long$vp=NULL
t_long = t_long %>% mutate(y_day= as.numeric(y_day)) 
t_long = t_long %>% mutate(day_of_year = mapply(ignore_leap_years,year,y_day))
t_long = t_long %>% mutate(date= make_date(year) + days(day_of_year-1))
t_long$y_day=NULL
t_long$day_of_year=NULL
t_long$value=round(t_long$value, digits=3)
write.table(t_long,paste0("D:/workspace/Winslow/iLand_AK/cpcrw/materials/climate/",model,"/",ssp,"/",model,"-",ssp,"-",var,"-",year,".txt"),row.names = F, sep = "\t")
}  


dir.create(paste0("D:/workspace/Winslow/iLand_AK/cpcrw/materials/climate/",gcm,"/ssp245"),recursive = T)

dir.create(paste0("D:/workspace/Winslow/iLand_AK/cpcrw/materials/climate/",gcm,"/ssp126"),recursive = T)

dir.create(paste0("D:/workspace/Winslow/iLand_AK/cpcrw/materials/climate/",gcm,"/ssp370"),recursive = T)


i="ssp126"
j="vp"
year=1950


for(i in levels(as.factor(c("ssp126","ssp245","ssp370")))){      
  for(j in levels(as.factor(c("hurs","pr","rsds","tasmax","tasmin","vp")))){          #
  for(year in 1950:2100){
  process.climate(gcm,i,j)
  print(paste0("Processed var ",j," and year ",year))
}
  }
}