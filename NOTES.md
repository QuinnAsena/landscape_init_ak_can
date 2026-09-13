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

### 2026-08-06 — Full-matrix round; steps-per-node stays at 3 (reasoning SUPERSEDED 2026-08-24, see below)
**Context:** Building the Derecho round that completes the 6 landscapes × 3 SSPs × 3 GCMs × onlysim grid — 270 cmdfile lines, 810 model runs after the 2026-08-13 revision to the full grid. Considered raising `--steps-per-node` from 3 to 4 to increase throughput.
**Decision/Finding:** Rejected. The usage report shows ~95% CPU at 3 steps × 40 threads, i.e. ~121 of 128 cores already busy, so the node is compute-bound. A fourth step divides the same saturated CPU four ways: throughput is identical at 0.379 lines per node-hour either way, while peak memory rises from 118–157 GB to ~209 GB against a 235 GB request and the walltime margin drops from 4.1 h to ~1.5 h. Concurrency now comes from node count — three independent chains split by landscape, 4 nodes × 3 steps = 12 concurrent reps each. Consequently `onlysim=true` uses 3 reps rather than 4 (replication is not the point there; 3 fills a node), which also keeps every batch a multiple of `--steps-per-node` so no node runs under-filled. Also added an optional 5th CSV argument and a `.complete` sentinel resume guard to `run_iland_csv_cpxml_apptainer.sh`; see `handover_2026-08-06_full-matrix-round.md` for the full change set and verification.
**Why:** Packing a CPU-saturated node buys no throughput while taking on both an OOM risk and a walltime-overrun risk. Full details, including why a resumed replicate must have its `scenario_dir` cleared first (unseeded reps produce different fire-event filenames, which would otherwise mix two realizations in one `rep_N/` folder), are in the handover document.
**Superseded 2026-08-24:** the "CPU-bound" premise was wrong. `threadCount` was inherited as `-1`, so each step took all 256 logical processors and three steps contended for 128 cores — the ~95% CPU was threads fighting, not work. A replicate stops getting faster at **8 threads**. The node is **memory-bound**, and on that basis steps-per-node moved to 4 on 2026-08-25. See `thread-scaling-test/report.md` and the 2026-08-27 entry below.

---

### 2026-08-27 — Measured Derecho resource use for spinup, scenario and processing jobs
**Context:** First `qhist` readings after moving scenario runs to `--steps-per-node 4` with an explicit `threadCount` of 16. Until now the 4-step memory figure was extrapolated from 3-step jobs.
**Decision/Finding:** Per node, per job kind:

| job | kind | steps/node | mem/node | GB/step | elapsed | walltime used |
|---|---|---|---|---|---|---|
| 7217938 | spinup lcp 01 | 3 | 146–154 GB | 49–52 | 4.78–5.10 h | 51% of 10 h |
| 7217939 | spinup lcp 02 | 3 | 133–138 GB | 44–46 | 5.02–5.33 h | 53% of 10 h |
| 7217940 | spinup lcp 03 | 3 | 149–154 GB | 50–51 | 6.12–6.36 h | 64% of 10 h |
| 7217941 | spinup lcp 04 (inferred) | 3 | 132–139 GB | 44–46 | 5.15–5.22 h | 52% of 10 h |
| 7240526 | scenario, chain A batch 1 | 4 | 180–211 GB | 45–53 | 9.64–10.76 h | **90% of 12 h** |
| 7240498 | area_dom processing | 9 | 79–90 GB | ~10 | 0.22–0.28 h | 14% of 2 h |

Scenario runs at 4 steps/node sit at **90% of both limits** — 211.34 of 235 GB and 10.76 of 12 h — so 5 steps is out and the margin cannot be bought with a longer walltime, since 12 h is effectively the cap (it is why each `fri` gets its own CSV). If it tightens, split CSVs to one GCM per line: ~3.6 h/line, 3× the lines, identical node-hours, better backfill. **Memory is flat across landscapes — snapshot size does not predict it in either direction.** Four spinup jobs spanning archived snapshots of 6.2–12.5 GB gave 132–154 GB/node, a 17% spread, and not monotonic: lcp 01 (12.5 GB) and lcp 03 (9.5 GB) are effectively equal. Job→landscape mapping confirmed from stdout on 2026-08-27 (7217938=01, 7217939=02, 7217940=03). An earlier version of this entry claimed the relationship was *inverted*; that came from mis-mapping job IDs and is retracted. Forecast chain C at **175–206 GB of 235** — the band chain A actually hit — rather than extrapolating from snapshot size. Per-step memory is stable at **44–53 GB across everything**, spinup or scenario, 300 years or 86. The 5 h spinup walltime would have killed jobs (6.36 h observed); the raise to 10 h was necessary. CPU% runs higher for spinups (33–35) than scenarios (24–28) despite fewer steps, consistent with scenarios writing every year and output being serial. **The threadCount fix cut CPU consumption 5.8× with no runtime cost** — 195 → 33 CPU-h per job, 39.2 → 6.1 cores busy of 128, wall time unchanged (all four landscapes in the 4.8–6.4 h band). So **83% of the CPU the node consumed was thread contention, not work.** Confirmed from job 7217939 stdout: `set 'system.settings.threadCount' to value '16'. result: '16'`. The landscape confound is ruled out — lcp 03 and 04 differ from 02 by up to 17% in memory yet all report ~33 CPU-h. This is why 4 steps/node became viable: at the old rate 4 steps would want ~52 cores of real work, at the new rate ~8, so memory is now the only constraint. **Note on Derecho behaviour:** edits to a cmdfile or the scripts it calls are picked up when a job RUNS, not when it was queued, so an afterok chain queued days earlier picks up changes pulled in the meantime.
**Why:** Every steps-per-node and walltime decision rests on these numbers, and they cost days of queue time to obtain. The 4-step memory extrapolation (165–210 GB) is now confirmed against measurement (180–211 GB).

---

### 2026-09-08 — A stuck PBS array parent stranded two chain-A batches; partial-chain resubmission added
**Context:** The 2026-09 Derecho maintenance window left job 7240530 (`cmdfile_chA_05.sh`) reporting state `B` even though all four of its array sub-jobs had ended. `afterok` never fires on a parent that has not reached a terminal state, so 7240531 (chA_06) and 7240532 (chA_07) were held indefinitely — 24 lines / 72 model runs that would never start.
**Decision/Finding:** The work itself was fine. The downloaded stdout (`stdout-7240530.desched1/`, 16 `step-*.out` files) showed every step running 3 GCMs, all **48 runs reaching `*** model run finished.`** with zero errors, and the stdout-derived run list matched the cmdfile-derived set exactly; the outputs were then confirmed on scratch. So maintenance cost no compute, only the parent's state. Recovery needed a way to submit *part* of a chain, because `submit_chain.sh A` submits all seven batches and the runner has no resume guard — it would have `rm -rf`'d the five that had completed. `submit_chain.sh` therefore gained an optional `start_batch` second argument (`submit_chain.sh A 6`), which validates the value, echoes the batch list with line counts before submitting, and is documented with the real hazard: **the batch you start FROM is re-run in full**, so `start_batch` must be the first batch that did *not* complete. chA_06/07 were resubmitted as 7349729/7349730. 7240531/7240532 had to be deleted **explicitly** — they did not cascade — and 7240530 itself could not be deleted at all (NCAR ticket open, also querying core-hour charging). **Tell NCAR to delete rather than requeue it:** the `launch_cf` we are calling submits `-r y`, so a requeue would re-run chA_05 and clobber 48 verified outputs. (Amended 2026-09-13: that is a property of the *copy* on our PATH, not of `launch_cf` in general -- NCAR made jobs non-rerunnable by default in June 2024 and updated the system `launch_cf` for it, so `Rerunable = True` is evidence we are on an old copy. See the 2026-09-13 entry.)
**Why:** two new tools came out of this and are worth knowing about. `analysis-scripts/check_cmdfile_complete.sh` expands a cmdfile through its CSVs and reports OK/PARTIAL/MISSING against the `.complete` sentinel, which is the only reliable completeness test since one line produces three output directories. `analysis-scripts/generate_process_cmdfiles.sh` generates processing cmdfiles by reading the run CSVs, so treatment names cannot drift from what the runs wrote — the failure mode that let `_yr_1_iLand2.1` persist. Downloaded job stdout is now gitignored via `stdout-*.desched*/`.

### 2026-09-13 — Chains A and B verified complete; batches collapsed 4 → 8 nodes for chain C
**Context:** Chains A and B finished (chB_07 / 7314032 ended 13-0638) with nothing left in the queue, and UCAR replied to the 7240530 ticket with three points: our jobs show `Rerunable = True` and we are probably on a local copy of `launch_cf`; we should use `-r n` or the system copy; and an `afterok` on an array predecessor should be `afterokarray`. Before committing chain C (landscapes 05, 06) we wanted the A/B output confirmed and a decision on whether the demonstrated concurrency justified bigger batches.
**Decision/Finding:** **All 528 model runs across the 11 scenario jobs in `std_out/` completed.** `running gcm` = `creating model` = `*** model run finished.` = 528, every step file holding exactly three GCMs (min 3, max 3), and **zero** matches for disk I/O errors, locked databases, OOM, aborts, segfaults or "failed". The only recurring stderr line is the known non-fatal iLand 2.1 `QSqlQuery::exec: database not open` (6 per step); the grep was sanity-checked against that string, so the zero-error result is real rather than a broken pattern. The two R `area_dom` jobs (7261547, 7349725) are clean too. **One gap:** no stdout was downloaded for 7240526/7240527 (chA_01, chA_02), so 32 lines / 96 runs of landscapes 01–02 are unverified from stdout — close that with `check_cmdfile_complete.sh`, which tests the `.complete` sentinel.

**32 concurrent steps is now measured, not extrapolated.** Deriving starts from qhist `End − Elap`, chB_04 (7314029, 08:46→18:44) and chA_06 (7349729, 10:09→18:43) overlapped ~10:12–16:33 on 2026-09-09, about 6 h 20 m with all 8 nodes busy. It cost nothing: 7.08–9.96 h elapsed and 137–166 GB/node under that load, against 8.06–9.91 h and 137–174 GB for a job running alone. Scratch I/O is the only resource two jobs share and it did not bite. Landscapes 03/04 also run cheaper than 01/02 (137–174 vs the 180–211 GB chain A hit at the same 4 steps/node), so snapshot size still fails to predict memory.

On that basis `NODES_PER_JOB` in `generate_cmdfiles.sh` moved **4 → 8**: a chain of 104 lines is now **3 batches of 32 plus one of 8** instead of 6 of 16 plus one of 8, cutting chain C from 7 batch turnarounds to 4 (~40 h of chained wall clock rather than ~70 h). Both 32 and 8 stay multiples of `STEPS_PER_NODE=4`, so no node is under-filled. **This is a batching change only and does not enlarge the allocation:** qhist shows each array subjob is `Nodes 1, NCPUs 128`, because `launch_cf` derives array size from lines ÷ steps-per-node and PBS schedules subjobs independently — a 32-line cmdfile is `-J 0-7`, eight separately scheduled single-node subjobs, not an 8-node reservation. Queue wait should therefore not worsen; the only cost is that the array parent reaches a terminal state on the slowest of 8 rather than the slowest of 4. Regeneration was verified content-neutral: all 312 command lines sorted are byte-identical before and after, only the grouping moved.

**Chain C was submitted with `submit_chain.sh` otherwise untouched — still plain `afterok`, still no `-r n`.** That is deliberate. The submission path is then identical to one that worked on every batch of A and B, and the single failure was a maintenance-window fluke with an existing recovery route (`start_batch` + `check_cmdfile_complete.sh`). An untested dependency string on the run we want out the door is the wrong risk: a malformed `afterokarray` would leave the whole chain unable to release. Job IDs were captured with `| tee scenario-launch/submit_log_chC.txt`, which needs no script edit and fixes the problem that chain A's job→cmdfile mapping had to be reconstructed by inference; `submit_log_*.txt` is gitignored.

**UCAR's two technical points are both valid and are deferred to a separate, tested change.** (1) `afterokarray`: `launch_cf` builds an array whenever a cmdfile spans more than one node, and both submit scripts use plain `afterok`. PBS Pro wants the array form. NCAR's own job-dependencies page documents only `after{,ok,notok,any}` and never mentions arrays, which is how this was missed. Their advice needs one caveat: a cmdfile that fits on one node produces a **non-array** job (7349725 had no `[]`), so the clause must be detected via `qstat -xf | grep 'array = True'`, not hard-coded. Prove it first with two throwaway 2-line cmdfiles at `--steps-per-node 1` and a `sleep 60` payload — about four node-minutes — confirming the dependent job releases unaided. (2) `-r n`: NCAR flipped the PBS default to non-rerunnable in June 2024 (arc.ucar.edu/articles/674), and that bulletin says *"the array launching command launch_cf has been updated for this"* — so `Rerunable = True` means an old copy, most likely `/glade/work/benkirk/repos/NCAR-pbstools/bin/launch_cf`, which our own legacy cmdfile comments still reference. `grep -nE -- '-r[ =]*y|rerun' "$(command -v launch_cf)"` settles it without a ticket round-trip; prefer pinning the system path over patching the flag, since an old copy may differ in other ways.
**Why:** the batch collapse is the cheapest throughput change available and it rests on a measurement that only existed because two chains happened to overlap. Keeping it separate from the PBS-correctness work means a chain C failure can only be attributed to one of the two changes.

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
