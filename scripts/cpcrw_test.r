library(terra)
library(ggplot2)
library(patchwork)
library(httpgd)

init_files <- list.files("D:/quinn/GitHub/landscape_init_ak_can/landscape_06/gis/init", full.names = TRUE)
cpcrw <- lapply(init_files, rast)

class_lookup <- c(
  "1" = "Black.spruce",
  "2" = "White.spruce",
  "3" = "Aspen",
  "4" = "Birch",
  "5" = "Mixed",
  "6" = "Potential-forest"
)

class_colours <- c(
  "1" = "#8c564b",
  "2" = "#1f77b4",
  "3" = "#2ca02c",
  "4" = "#00ff00",
  "5" = "#9467bd",
  "6" = "#bcbd22"
)


plot_class <- function(raster, class_val) {

  df <- as.data.frame(raster, xy = TRUE)
  df$mask <- ifelse(df$forest_species_init == class_val,
                    as.character(class_val), NA)

  ggplot(df, aes(x = x, y = y, fill = mask)) +
    geom_raster() +
    coord_equal(expand = FALSE) +
    scale_fill_manual(
      values = class_colours,
      labels = class_lookup,
      na.value = "white"
    ) +
    labs(title = class_lookup[as.character(class_val)]) +
    theme_minimal() +
    theme(
      axis.text = element_blank(),
      axis.title = element_blank(),
      legend.position = "none"
    )
}

# Loop over the 6 classes
plots1 <- lapply(1:6, \(cl) plot_class(cpcrw[[1]], cl) + ggtitle(paste(class_lookup[cl], "1984")))
plots2 <- lapply(1:6, \(cl) plot_class(cpcrw[[2]], cl) + ggtitle(paste(class_lookup[cl], "2014")))

paired_plots <- lapply(1:6, function(i) {
  (plots1[[i]] | plots2[[i]])
})

panel1 <- (plots1[[1]] | plots2[[1]]) /
          (plots1[[2]] | plots2[[2]])

panel2 <- (plots1[[3]] | plots2[[3]]) /
          (plots1[[4]] | plots2[[4]])

panel3 <- (plots1[[5]] | plots2[[5]]) /
          (plots1[[6]] | plots2[[6]])