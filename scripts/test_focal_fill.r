library(terra)

# Temporary test script for the focal zero-fill used in process_soil.
# Demonstrates on a small synthetic grid that:
#   1. zero-total cells (all three textures == 0) are filled from neighbours
#   2. all other cells are left exactly unchanged
# Run this interactively and compare before/after values and plots.

set.seed(42)
n <- 20   # small grid — output is easy to inspect

# Helper: create a raster of random values in [lo, hi]
make_rast <- function(lo, hi) rast(nrows = n, ncols = n, vals = runif(n * n, lo, hi))

# Three texture rasters with realistic but arbitrary ranges (g/kg ÷ 10 = %).
# These do NOT need to sum to 100 — normalisation handles that later in the pipeline.
sand <- make_rast(20, 60)
silt <- make_rast(10, 40)
clay <- make_rast(5, 20)

# ── Inject known zero-cells ────────────────────────────────────────────────
# Simulate the rocky patches in landscapes 03/05 where SoilGrids records
# exactly 0 for all three textures.
# Two clusters + one isolated cell, so we can test both scenarios.
zero_cells <- c(45, 46, 65, 66,   # 2x2 cluster
                200)               # isolated single cell

values(sand)[zero_cells] <- 0
values(silt)[zero_cells] <- 0
values(clay)[zero_cells] <- 0

# ── Before fix ────────────────────────────────────────────────────────────
total_before <- sand + silt + clay
cat("=== Before fix ===\n")
cat("Cells with total == 0:", global(total_before == 0, "sum")$sum,
    " (expect", length(zero_cells), ")\n")
cat("Cell 45  — sand:", round(values(sand)[45], 2),
    " silt:", round(values(silt)[45], 2),
    " clay:", round(values(clay)[45], 2), "\n")
cat("Cell 200 — sand:", round(values(sand)[200], 2),
    " silt:", round(values(silt)[200], 2),
    " clay:", round(values(clay)[200], 2), "\n\n")

# ── Apply fix ─────────────────────────────────────────────────────────────
# This mirrors the code added to process_soil after names(processed) <- soil_vars.

# Step 1: identify cells where ALL THREE textures are simultaneously 0.
# A cell with sand=0, silt=5, clay=10 has total=15 — NOT included.
zero_mask <- (sand + silt + clay) == 0
plot(zero_mask)

soil_list <- list(sand = sand, silt = silt, clay = clay)

lapply(soil_list, as.matrix, wide = TRUE)

filled <- lapply(soil_list, function(r) {

  # Set zero-total cells to NA so focal() treats them as missing.
  # Valid cells (total > 0) retain their original values unchanged.
  r_na <- ifel(zero_mask, NA, r)

  terra::focal(
    r_na,
    w   = 3,         # 3x3 pixel window: the centre cell plus its 8 immediate
                     # neighbours (up/down/left/right/diagonal)
    fun = "mean",    # fill value = arithmetic mean of available window cells
    na.rm  = TRUE,   # if some neighbours are themselves NA (e.g. clustered
                     # zeros), use whichever neighbours do have valid values;
                     # a window with NO valid neighbours returns NA
    na.policy = "only"   # ONLY update cells that are currently NA — all other
                         # cells are passed through exactly as-is; without this
                         # argument focal() would smooth the ENTIRE raster
  )
})

lapply(filled, as.matrix, wide = TRUE)


# ── After fix ─────────────────────────────────────────────────────────────
total_after <- filled$sand + filled$silt + filled$clay

cat("=== After fix ===\n")
cat("Cells with total == 0:", global(total_after == 0, "sum")$sum, " (expect 0)\n")
cat("Cell 45  — sand:", round(values(filled$sand)[45], 2),
    " silt:", round(values(filled$silt)[45], 2),
    " clay:", round(values(filled$clay)[45], 2),
    " (were all 0; now interpolated from neighbours)\n")
cat("Cell 200 — sand:", round(values(filled$sand)[200], 2),
    " silt:", round(values(filled$silt)[200], 2),
    " clay:", round(values(filled$clay)[200], 2),
    " (were all 0; now interpolated from neighbours)\n\n")

# ── Verify non-zero cells are unchanged ───────────────────────────────────
# na.policy = "only" guarantees this, but confirm it explicitly.
# For every cell where zero_mask == FALSE, the filled value must equal the
# original value to floating-point precision.
non_zero <- !as.logical(values(zero_mask))
sand_ok <- all(abs(values(filled$sand)[non_zero] - values(sand)[non_zero]) < 1e-9, na.rm = TRUE)
silt_ok <- all(abs(values(filled$silt)[non_zero] - values(silt)[non_zero]) < 1e-9, na.rm = TRUE)
clay_ok <- all(abs(values(filled$clay)[non_zero] - values(clay)[non_zero]) < 1e-9, na.rm = TRUE)
cat("Non-zero cells unchanged — sand:", sand_ok, " silt:", silt_ok, " clay:", clay_ok,
    " (all should be TRUE)\n\n")

# ── Visual check ──────────────────────────────────────────────────────────
# The zero-cells should appear as visible patches in the 'before' plots
# and blend smoothly into their surroundings in the 'after' plots.
par(mfrow = c(2, 3))
plot(sand,        main = "sand  — before", range = c(0, 65))
plot(silt,        main = "silt  — before", range = c(0, 45))
plot(clay,        main = "clay  — before", range = c(0, 25))
plot(filled$sand, main = "sand  — after",  range = c(0, 65))
plot(filled$silt, main = "silt  — after",  range = c(0, 45))
plot(filled$clay, main = "clay  — after",  range = c(0, 25))
