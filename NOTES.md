# NOTES

Running log of decisions, gotchas, and non-obvious implementation details.
Full spatial methodology is in `description.qmd`.

---

## Template

```
### YYYY-MM-DD — Short title
**Context:** What was being worked on.
**Decision/Finding:** What was decided or discovered.
**Why:** Reason or constraint.
```

---

## Resolved Spatial Challenges

### Grid alignment (stand.grid ↔ env.grid)
- A snap grid (100×100 and 10×10) was introduced to ensure pixel-exact alignment between the stand grid and environment grid.
- Direct CRS reassignment after `disagg()` caused misalignment; solution uses explicit reprojection.
- Details: `description.qmd`, scripts `02` and `10–11`.

### Landscape buffering for climate and DEM
- in order to create the climate link file, the climate data are buffered to a larger area than the environment grid and then extracted against the grid points. The alternative of interpolating the climate to the resources unit grain works but creates files that are 100 times larger.
- DEM data are also downloaded to a buffered area in order to calculate aspect without edge pixels becoming NA.

### terra quirks
- Various `terra` version-specific behaviours encountered and resolved; specifics documented inline in scripts.

---

## ABoVE surface water data artefacts (script 09)

### 2026-04-24 — All-water epochs in ABoVE surface water tiles
**Context:** Running `09_species_init.r` across all 31 land cover years revealed that
certain landscape/decade combinations produce a surface water raster where every cell
equals 1 (all-water), rather than the expected classes: 0 = land, 1 = Water,
2 = probable water in Alaska1991 tiles, 255 = No data.
**Decision/Finding:** This is a documented data quality issue. The ABoVE Water Map
Alaska 1991 fill procedure (applied to tiles h00v00, h00v01, h01v00) can propagate
water values (value 2 = probable water) across areas with no 1991 observations. For
some landscapes this results in an all-water epoch for one or more decades.
Map file cell values: 0 = land, 1 = water, 2 = probable water (Alaska 1991 tiles
only), 255 = no data. Value 2 is treated as water in the masking step.
**Why:** A decade where all cells equal 1 produces a mask that eliminates the entire
landscape, which is incorrect. The fix (in `09_species_init.r`) validates each decade
before use: a valid decade must have both land (0) and water (1/2) cells. If the
nominated decade is invalid, the nearest valid decade is used instead. If all three
decades are invalid, the script falls back to ABoVE land cover class 15 (water) to
derive the 50m buffer mask.

---

## HPC Deployment (Derecho)

### 2026-06-03 — Sequential batch submission via PBS afterok dependency chain
**Context:** Running all 36 remaining replicates (landscapes 03–06, reps 4–12) in parallel caused disk I/O contention on Derecho scratch. The working limit is 6 reps at a time (2 nodes × 3 reps/node via `launch_cf --steps-per-node 3`).
**Decision/Finding:** Automated sequential submission using PBS `afterok` dependency chaining. `submit_chain.sh` splits the 36 commands across 6 cmdfiles (`cmdfile_b01.sh`–`cmdfile_b06.sh`, 6 lines each) and chains them: each batch is held (`H`) until the previous finishes. `launch_cf` passes unrecognised flags through to `qsub`, so `-W depend=afterok:JOBID` works directly. Critical gotcha: `launch_cf` prints verbose diagnostic text to stdout before the job ID, so the job ID must be extracted with `| tail -1` when capturing via `$()`.
**Why:** Queue wait times of 12–18 hours make manual re-submission expensive; the chain runs unattended once submitted.

### 2026-08-06 — Full-matrix round; steps-per-node stays at 3 because the node is CPU-bound
**Context:** Building the Derecho round that completes the 6 landscapes × 3 SSPs × 3 GCMs × onlysim grid — 270 cmdfile lines, 810 model runs after the 2026-08-13 revision to the full grid. Considered raising `--steps-per-node` from 3 to 4 to increase throughput.
**Decision/Finding:** Rejected. The usage report shows ~95% CPU at 3 steps × 40 threads, i.e. ~121 of 128 cores already busy, so the node is compute-bound. A fourth step divides the same saturated CPU four ways: throughput is identical at 0.379 lines per node-hour either way, while peak memory rises from 118–157 GB to ~209 GB against a 235 GB request and the walltime margin drops from 4.1 h to ~1.5 h. Concurrency now comes from node count — three independent chains split by landscape, 4 nodes × 3 steps = 12 concurrent reps each. Consequently `onlysim=true` uses 3 reps rather than 4 (replication is not the point there; 3 fills a node), which also keeps every batch a multiple of `--steps-per-node` so no node runs under-filled. Also added an optional 5th CSV argument and a `.complete` sentinel resume guard to `run_iland_csv_cpxml_apptainer.sh`; see `handover_2026-08-06_full-matrix-round.md` for the full change set and verification.
**Why:** Packing a CPU-saturated node buys no throughput while taking on both an OOM risk and a walltime-overrun risk. Full details, including why a resumed replicate must have its `scenario_dir` cleared first (unseeded reps produce different fire-event filenames, which would otherwise mix two realizations in one `rep_N/` folder), are in the handover document.

---

## Fire Regime Analysis Script

### 2026-07-05 — process_fire_regime.R Sections 5–6 verified
**Context:** `analysis-scripts/process_fire_regime.R` ports `fire-regime_script-5_09-30-2022.Rmd` (sp/raster/rgdal/rgeos → terra, CPCRW hardcoding → CLI args). Sections 1–4 were already ported and saving the outputs needed. Sections 5 (AK-wide grid FRP reference distribution) and 6 (rolling FRP for the selected replicate) are the newest/most complex terra ports and hadn't had a focused correctness pass.
**Decision/Finding:** Reviewed Sections 5–6 against the original Rmd logic and ran Section 5 end-to-end against the real local historical fire shapefiles (`data/historic_fire/raw_data/fire/`) — no HPC data needed since Section 5 is landscape-independent. Confirmed: `AK_polygon.shp` and `boreal_domain.shp` are both single-feature layers, so `terra::relate(...)[, 1]` land/boreal masking is correct; `boreal_domain.shp` living in the same `dsn` fire directory is correct (data already consolidated there); grid extent built from full `histfire` vs. the Rmd's year-filtered `histfire_yr` produces an identical bounding box in practice, so that deviation has no effect. Section 6's `vapply` rolling-FRP loop is a faithful, smoke-tested translation of the Rmd's `for` loop. No bugs found, no code changes needed.
**Why:** `process_fire_regime_reference.R` (the old sandbox/validation script for these sections) is being removed — this pass confirms Sections 5–6 are correct on their own merits rather than relying on that reference script.

---

## Climate sampling

### 2026-08-13 — Scenario runs were resampling climate years; randomSampling now branch-scoped
**Context:** `13_project_file_create.r` called `sample_climate()` unconditionally, so scenario XMLs inherited the spinup's resampling setup.
**Decision/Finding:** Every scenario XML carried `randomSamplingEnabled=true` (the master XML default, never overridden) plus an 86-entry `randomSamplingList` of 0-based indices drawn with replacement from 2015–2100 — so model year 1 used climate 2017, year 2 used 2028, and so on. The distribution of years was correct but the warming trajectory was destroyed. Now the climate keys are set inside each `run_type` branch: spinup forces `randomSamplingEnabled=true` with its list and batchYears; scenario sets the year filter, forces `false`, leaves the list blank, and sets `batchYears` to 50. All six `_2015-2100scenario.xml` files regenerated 2026-08-13 and verified.

`batchYears` is a climate read-buffer size (years loaded per database query), not a sampling control — leaving it empty can fall back to a 1-year buffer and slow the run with constant disk I/O, so 50 is set explicitly. It is safe for it to be below the 86-year run length only because sampling is off; with `randomSamplingEnabled=true` it would also cap the climate to the first N years of the record. The two keys are coupled and must be changed together.
**Why:** the resampling machinery is correct for spinup (resample 1950–1980 across 300 years) but wrong for scenarios, whose entire purpose is the trend. All previously completed scenario runs — the July ssp245 Derecho rounds and the local `_onlyfire` runs — are affected and must be redone. The `_onlyfire` XMLs still carry the old settings because that generation loop is commented out.

**Watch out when editing this block:** moving `climate_settings <- sample_climate(...)` into a branch while leaving a reader above the `if` does not fail loudly. R does not hoist locals, so the read falls through to the global environment — with a stale global present it silently writes the wrong filter for both run types, and only in a clean session does it error. Verify changes against the generated XML, not just the R source.

---

## Scenario output naming

### 2026-08-17 — `fri` added to the scenario identifier; `yr_1_iLand2.1` dropped
**Context:** `fri` was lowered from 120 to 60 in `iland_scenarios_onlyfire.csv` for the local runs, but the identifier that names output directories, temp XMLs and output databases was `${gcm}_dbh${dbh}_onlysim${onlysim}_${id}` — no `fri` token. The fri=60 runs therefore resolved to the same paths as the fri=120 runs and silently overwrote them. `iland_scenarios_onlyfire.csv` now carries both FRIs in one file (120 with `onlysim=true`, 60 with `onlysim=false`), which only the new naming makes safe.
**Decision/Finding:** Both runners (`run_iland_csv_cpxml.sh`, `run_iland_csv_cpxml_apptainer.sh`) now build the name once, as
`scenario_id="${gcm}_dbh${dbh}_onlysim${onlysim}_fri${fri}${id:+_${id}}"`,
and use `${scenario_id}` for `scenario_dir`, `tmp_xml`, `out_db` and `system.database.out`. The `id` token is now optional — the `id` column was blanked in all seven Derecho CSVs (`iland_scenarios.csv` and the six `iland_scenarios_ssp*_sim*.csv`), so `yr_1_iLand2.1` is gone from every path, while `iland_scenarios_onlyfire.csv` keeps its `onlyfire` tag. Resulting forms:

```
NorEsm2-MMssp245_dbh2.5_onlysimtrue_fri120                 # Derecho
TaiESM1ssp370_dbh2.5_onlysimfalse_fri60_onlyfire           # local
```

`fri` is appended *after* `onlysim` so the cleanup glob `landscape_alaska_0*/*_dbh2.5_onlysim*.xml` in `submit_chain.sh` still matches. `fri` comes from CSV column 3 only — no runner argument changed, so `run_iland_local.sh` and `generate_cmdfiles.sh` call sites are untouched.

**Note the archive uses the opposite order.** The fri=60 runs hand-archived in July under `landscape_alaska_01/output/archive/` are named `..._onlysimfalse_onlyfire_fri60` — `fri` *after* the id, not before it. Deliberate choice to keep the runner as `..._onlysimfalse_fri60_onlyfire`; do not assume a single token order when globbing across `output/` and `output/archive/`.
**Why:** `fri` is a treatment in this experiment, so it belongs in the identifier; without it the same overwrite would hit Derecho the first time a second FRI is run there. Building the name once also stops `out_db` and `system.database.out` from drifting apart, which would silently disable the local resume guard.

**Two consequences to watch:**
- The Derecho `.complete` sentinel is looked up under the new name, so reps already finished under an old-name directory are invisible and will be re-run into new directories. Old directories are left in place (they hold the fri=120 output) and must be removed by hand once a re-run lands. Check whether a chain is mid-flight before deploying the changed runner.
- The analysis cmdfiles in `analysis-scripts/` (`cmdfile_process_area_dom.sh`, `cmdfile_process_basal_area.sh`, `cmdfile_process_seed_dens.sh`) and the fallback `treatment` strings in `process_dbh.R` / `process_fire_regime.R` still hard-code the old `..._onlysimtrue_yr_1_iLand2.1` literals. These were deliberately **not** updated — they point at output that already exists on scratch under the old name. Any cmdfile written for output produced after 2026-08-17 must use the new form, e.g. `NorEsm2-MMssp245_dbh2.5_onlysimtrue_fri120`. The R scripts take the treatment as an opaque CLI string and never split it into fields, so the extra token breaks no parsing.

---

## Spinup output volume and runtime

### 2026-08-21 — The `tree` output is 95% of a spinup database and half its runtime
**Context:** the 300-year spinups were producing 300-500 GB output databases and taking ~7.3 h
on Derecho. Script 13's spinup block was changed on 2026-08-19 to disable four of the six
output blocks (`tree`, `sapling`, `carbon`, `water`; `stand` and `saplingdetail` kept), and a
local timing run then finished in 1 h 32 m with a 25 GB database. `analysis-scripts/derecho-spotcheck.R`
was written to attribute the difference per table without reading any table into memory.

**Finding — it is almost entirely `tree`.** On the old full-output spinup (landscape_03 rep_3,
412.92 GB): `tree` 2.58 billion rows apportioning to ~391 GB, i.e. 94.6% of the file.
`saplingdetail` 19.8 GB, `stand` 1.0 GB, and the other three disabled tables — `carbon` 0.64,
`sapling` 0.49, `water` 0.30 — total 1.4 GB between them. Disabling `carbon`/`sapling`/`water`
saved nothing worth having; disabling `tree` saved ~391 GB.

The timers say the same thing. `TreeOut::exec()` was 3 h 32 m of the old run — 82% of its
4 h 17 m `outputs` timer and ~48% of the entire 7 h 18 m wall clock — and is absent from the
new run entirely.

**`tree` is not a filter bug.** It was suspected of saving all 300 years rather than the
`filt_cond = 260` window. It was not: `carbon` and `water` are per-RU-per-year tables and both
had exactly 2,514,243 rows, which is 61,323 RUs x 41 years exactly, so the filter applied.
`tree` is 2,579,534,174 / 2,514,243 RU-years = ~1026 trees per RU per year, a realistic
mature-stand stem density. The table is inherently enormous because it is one row per
individual tree per year.

**Runtime expectation on Derecho: ~3.5-4 h, not 1.5 h.** The local 1 h 32 m had the whole
machine; the old Derecho run shared a node at `--steps-per-node 3`. Non-output time alone fell
3 h 01 m -> 1 h 07 m between them, a 2.7x gap that is hardware and node sharing, not outputs.
Budget ~3 h compute plus reduced output time against the 12 h walltime.

**Disk is now the binding constraint, not walltime.** ~25 GB output + ~10 GB snapshot per
replicate, so 54 replicates is ~1.9 TB on scratch. Eight of the nine snapshots per landscape
are discardable once a replicate is chosen for `landscape_nn/snapshot/`, which is ~480 GB of
that total.

**KBDIref is visible in the snapshot, in the intended direction.** Same landscape (01), same
climate seed, KBDIref 0.038 -> 0.029: `trees` 91.6 M -> 68.4 M (-25.3%), `saplings`
88.2 M -> 95.0 M (+7.7%), file 12.50 -> 10.12 GB. Fewer mature trees and more regeneration is
the signature of more fire, which is what lowering the reference value should do. `snag` and
`soil` stayed identical at 60,462 rows — they are one row per simulated RU, so that is the
control confirming the landscape geometry did not move.

That 60,462 also independently confirms the KBDI zero-cell diagnosis: landscape_01 has 60,573
in-footprint cells, 111 of which are always-zero KBDI, leaving exactly 60,462 simulated RUs.
Two unrelated measurements agree.

**How to measure this without a login-node OOM:** `dbstat` is unavailable (RSQLite is not built
with `SQLITE_ENABLE_DBSTAT_VTAB`), and `collect()` on a `water` table will not fit in memory.
Instead `max(rowid)` gives the row count from the rightmost b-tree page in O(log n), and the
payload byte sum is computed inside SQLite over a `LIMIT`ed sample so only one number is
returned. Year ranges come from evenly spaced `where rowid = ?` seeks, exploiting the fact that
iLand appends in year order. 35 GB across two databases profiled in 0.58 s with flat memory.
The seeks are latency-bound, so keep the probe count low.


### 2026-08-21 — Old spinup snapshots archived out of reach of the project files
**Context:** the six `landscape_alaska_NN/snapshot/spinup_300.sqlite` files were produced
May-July 2026 with `<KBDIref>` at the master default of 0.038 for every landscape. The 2026-08
round replaces that with a per-landscape value (01 0.029, 02 0.026, 03 0.032, 04-06 0.030), so
those snapshots are superseded — but the scenario CSVs reference `snapshot_file =
snapshot/spinup_300`, and the files still sat at exactly that path.
**Decision/Finding:** moved each to
`landscape_alaska_NN/snapshot/archive_2026-05_kbdiref-default-0.038/spinup_300.sqlite` with a
per-landscape `README.md` recording the KBDIref used, the file size, and the `trees` /
`saplings` / `snag` / `soil` row counts. 62.73 GB total, all six untracked by git so the move
created no churn.
**Why:** the window between the new spinups finishing and their snapshots being collected was
a silent-failure trap. A scenario run launched in that window would have started from the
0.038 state with nothing to indicate it — no error, no warning, just the wrong initial
conditions. With the file moved, iLand fails on a missing `snapshot/spinup_300.sqlite`
instead. A loud failure is the whole point of the move.

**Bonus confirmation, all six landscapes.** `snag` and `soil` hold one row per simulated
resource unit, and those counts match the KBDI-nonzero cell counts in
`data/kbdi_summary/kbdi_summary.csv` **exactly** for every landscape — 60,462 / 61,470 /
61,322 / 60,666 / 61,588 / 61,747. Two entirely unrelated measurements agreeing six times over
settles the earlier zero-cell diagnosis: KBDI > 0 identifies precisely the RUs iLand simulates.

**Gotcha for anyone reusing `derecho-spotcheck.R`:** `select min(rowid), max(rowid) from tbl`
in one query **full-scans the table**. SQLite's min/max optimisation only fires when the query
holds exactly one aggregate — `EXPLAIN QUERY PLAN` shows `SEARCH` for either alone and `SCAN`
for both together. That is 0.05 s versus 136 s on a 466 M-row table locally, and it never
finished against a 412 GB table on a Derecho login node. Split it into two queries.

---

## Known Fragilities (from `issues-codex5.3.md`)

Not urgent for controlled pipeline runs, but worth awareness:

- **Script 00/01:** Column name inconsistency (`Propforested` vs `Propforest`, `Suppression` spelling)
- **Script 10:** `sapinit_dict` written to empirical input folder — should go to output folder
- **Script 12:** Climate table-name contract (RU-keyed vs climate-grid-keyed) needs locking
- **Scripts 05/06/11/12:** Missing input validation (optional hardening)
