library(dplyr)
library(tidyr)
library(purrr)
library(fitdistrplus)

johnstone <- read.table("C:/Users/asenaq/Documents/GitHub/landscape_init_ak_can/data/empirical/Alaska-init-stands-johnstone.txt", header = TRUE, sep= ",")
walker <- read.table("C:/Users/asenaq/Documents/GitHub/landscape_init_ak_can/data/empirical/Alaska-init-stands-walker.txt", header = TRUE, sep= "\t")
heights <- read.table("C:/Users/asenaq/Documents/GitHub/landscape_init_ak_can/data/empirical/Johnstone_tree_heights.txt", header = TRUE, sep = "\t")


#---------- Proportions and densities ----------#
johnstone <- johnstone |>
  dplyr::mutate(dataset = "johnstone") |>
  tidyr::unite("Site_name", c("dataset", "site"), sep = "_") |>
  dplyr::select(Site_name, BS.dens, TA.dens, PB.dens, total.dens,
         BS.prop = bs.prop, TA.prop = ta.prop, PB.prop  = pb.prop)

walker <- walker |>
  dplyr::mutate(dataset = "walker") |>
  tidyr::unite("Site_name", c("dataset", "burnsite"), sep = "_") |>
  dplyr::select(Site_name, BS.dens = BS.dens.post, TA.dens = TA.dens.post,
         PB.dens = PB.dens.post, total.dens, BS.prop = bs.prop,
         TA.prop = ta.prop, PB.prop = pb.prop)

johnstone_walker <- bind_rows(johnstone, walker) |>
  drop_na(BS.prop)
rownames(johnstone_walker) <- NULL


johnstone_walker_classified <- johnstone_walker |>
  mutate(
    forest_type = case_when(
      BS.prop >= 0.75 ~ "bs",
      TA.prop >= 0.75 ~ "ta",
      PB.prop >= 0.50 ~ "pb",
      BS.prop >= 0.25 & BS.prop < 0.75 ~ "mixed",
    #   BS.prop >= 0.25 & BS.prop < 0.75 &
    #     (TA.prop + PB.prop) >= 0.25 &
    #     (TA.prop + PB.prop) <= 0.75 ~ "mixed",
      TRUE ~ NA_character_
    )
  )

# The above code is slightly different from Winslow's original in that
# case_when forces exclusivity of the caregories (original below).
# The difference is only a few duplicates (6) in "mixed"
# bs = total %>% filter(BS.prop>=0.75)
# ta = total %>% filter(TA.prop>=0.75)
# pb = total %>% filter(PB.prop>=0.50)
# mixed = total %>% filter(BS.prop<=0.75&BS.prop>=0.25&TA.prop+PB.prop<=0.75&TA.prop+PB.prop>=0.25)

#---------- Heights ----------#
dist_dict <- tibble(
  species = c("spruce", "aspen", "birch"),
  distr   = c("gamma",  "gamma", "weibull")
)

heights <- dist_dict |>
  inner_join(heights, by = "species") |>
  group_by(species, distr)

params <- heights |>
  group_split() |>
  setNames(heights |> group_keys() |> dplyr::pull(species)) |>
  purrr::imap(\(df, sp) {
    fitdistrplus::fitdist(df$height, df$distr[[1]])
  })






spruce_heights <- heights_split$spruce
d <- density(spruce_heights$height)
plot(d)
est   <- params$spruce$estimate
distr <- "gamma"

curve(dgamma(x,
         shape = est["shape"],
         rate  = est["rate"]),
  add = TRUE,
  col = "blue"
)








heights.y <- heights %>% filter(species == "spruce")
distr <- "gamma"
fitdistrplus::fitdist(heights.y$height, distr)


estimate_ht_param = function(species,distr){
heights.y=heights%>%filter(species==species)
fg=fitdistrplus::fitdist(heights.y$height,distr)
return(fg)
}


bs.param=estimate_ht_param("spruce","gamma")
ta.param=estimate_ht_param("aspen","gamma")
pb.param=estimate_ht_param("birch","weibull")

bs.height=heights%>%filter(species=="spruce")
d=density(bs.height$height)
plot(d)
curve(dgamma(x,shape=3.8,rate=0.101), ##1.86580232   0.02615085
      add=TRUE,
      col="blue")

ta.height=heights%>%filter(species=="aspen")
d=density(ta.height$height)
plot(d)
curve(dgamma(x,shape=1.96,rate=0.031), ##1.86580232   0.02615085
      add=TRUE,
      col="blue")

pb.height=heights%>%filter(species=="birch")
d=density(pb.height$height)
plot(d)
curve(dweibull(x,shape=2.011525,scale=188.487756), ##1.86580232   0.02615085
      add=TRUE,
      col="blue")