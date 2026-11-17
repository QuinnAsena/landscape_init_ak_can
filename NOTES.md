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
**Decision/Finding:** **All 528 model runs across the 11 scenario jobs in `std_out/` completed.** `running gcm` = `creating model` = `*** model run finished.` = 528, every step file holding exactly three GCMs (min 3, max 3), and **zero** matches for disk I/O errors, locked databases, OOM, aborts, segfaults or "failed". The only recurring stderr line is the known non-fatal iLand 2.1 `QSqlQuery::exec: database not open` (6 per step); the grep was sanity-checked against that string, so the zero-error result is real rather than a broken pattern. The two R `area_dom` jobs (7261547, 7349725) are clean too. **Gap closed the same day:** the user downloaded the missing 7240526/7240527 (chA_01, chA_02) stdout, and both are equally clean — 16 steps each, 48/48/48 started/created/finished, 3 GCMs per step, no errors. **Coverage is now complete: 624 of 624 runs across both chains.** Those two directories also *confirm* the chain A job→cmdfile mapping that `project-chain-job-ids` had only inferred: 7240526–528 are pure landscape 01, 7240529 straddles the 01→02 boundary, 7240530 is pure landscape 02 — exactly what a 52/52 line split at 16 lines per batch predicts.

**32 concurrent steps is now measured, not extrapolated.** Deriving starts from qhist `End − Elap`, chB_04 (7314029, 08:46→18:44) and chA_06 (7349729, 10:09→18:43) overlapped ~10:12–16:33 on 2026-09-09, about 6 h 20 m with all 8 nodes busy. It cost nothing: 7.08–9.96 h elapsed and 137–166 GB/node under that load, against 8.06–9.91 h and 137–174 GB for a job running alone. Scratch I/O is the only resource two jobs share and it did not bite. Landscapes 03/04 also run cheaper than 01/02 (137–174 vs the 180–211 GB chain A hit at the same 4 steps/node), so snapshot size still fails to predict memory.

On that basis `NODES_PER_JOB` in `generate_cmdfiles.sh` moved **4 → 8**: a chain of 104 lines is now **3 batches of 32 plus one of 8** instead of 6 of 16 plus one of 8, cutting chain C from 7 batch turnarounds to 4 (~40 h of chained wall clock rather than ~70 h). Both 32 and 8 stay multiples of `STEPS_PER_NODE=4`, so no node is under-filled. **This is a batching change only and does not enlarge the allocation:** qhist shows each array subjob is `Nodes 1, NCPUs 128`, because `launch_cf` derives array size from lines ÷ steps-per-node and PBS schedules subjobs independently — a 32-line cmdfile is `-J 0-7`, eight separately scheduled single-node subjobs, not an 8-node reservation. Queue wait should therefore not worsen; the only cost is that the array parent reaches a terminal state on the slowest of 8 rather than the slowest of 4. Regeneration was verified content-neutral: all 312 command lines sorted are byte-identical before and after, only the grouping moved.

**Chain C went out on the batching change ALONE — plain `afterok`, no `-r n`.** Submitted 2026-09-13 as **7431373–7431376** (chC_01–04), batch 1 `Q` and 2–4 `H`. `afterokarray` was drafted and then deliberately held back: the user's call was that the batch collapse was the change worth testing on a 12-hour-queue job, and that the dependency clause belongs on a cheap test bed. `array_dep` is therefore present in `submit_chain.sh` but **not wired in**, with the one-line swap noted beside the call. `submit_chain_spinup.sh` is likewise untouched.

**The area_dom processing chain is that test bed** — it clears the queue in ~1–2 h, so a rejected dependency costs minutes rather than a 12 h slot. **One trap there: processing cmdfiles are not all arrays.** The scenario ones are 156 lines at 12 steps/node = 13 nodes, but the spinup ones are 9 lines at 18 steps/node = **one node**, i.e. a plain job with no `[]` — which is exactly why 7349725 had none. `afterokarray` on a non-array predecessor is rejected, so a chain mixing the two needs the `qstat -xf | grep 'array = True'` detection, not the unconditional helper. Neither *submit* script needs that, because every cmdfile they chain spans 2+ nodes.

Worth recording for whenever the switch happens: the failure mode is safe and loud. A rejected dependency string fails at *submission* of batch 2, `set -e` aborts, and batch 1 is already queued and unaffected. Recovery is `submit_chain.sh <chain> 2` — but **wait for batch 1 to finish first**, because `start_batch` submits its first batch with no dependency, so batches 2+ would otherwise run alongside batch 1 at 64 concurrent steps, double anything measured.

**Three things the chain C submission settled, which had been open questions.** (a) **The job ID format is `7431373[].desched1`** — brackets *and* server suffix. So `array_dep`'s normalisation is correct for the real format, and a literal `afterok` → `afterokarray` swap would have been too; the helper is kept because it holds for all four plausible formats at no cost. (b) **`afterok` is accepted on a bracketed array ID** and holds the successors properly (batches 2–4 went straight to `H`), so nothing about the clause is malformed today — it is only the stuck-parent edge case that is in question. (c) **The batch collapse behaves exactly as predicted**: `-J 0-7` on the three 32-line batches, `-J 0-1` on the 8-line tail, each subjob requesting `select=1:ncpus=128:mpiprocs=4:ompthreads=16:mem=235GB` — one node per subjob, confirming this was a batching change and not a larger allocation.

**Progress by 2026-09-15: batches 1–2 done, 7431375 running (`B`), 7431376 held.** `afterok` released cleanly twice in a row here (7431373 → 7431374 → 7431375), further evidence that it is fine in normal operation and that only the stuck-parent case is at issue. **Landscape 05 is therefore complete and landscape 06 is not:** the generator emits landscapes in order, so all 52 of lcp 05's lines sit in batches 1–2 (32 + 20), while lcp 06's 52 are split 12 / 32 / 8 across batches 2–4. So **01–05 are ready for area_dom post-processing and 06 has 40 lines outstanding** — a useful accident of the 8-node batching, since at the old 16-line size the landscape boundary fell mid-batch differently.

**WALLTIME MARGIN IS THE TIGHTEST IT HAS BEEN — watch it.** Chain C is running hotter than either predecessor:

| job | mem/node | elapsed | of 12 h |
|---|---|---|---|
| 7240526 (chain A, lcp 01/02) | 180–211 GB | 9.64–10.76 h | 90% |
| 7314028–032 (chain B, lcp 03/04) | 137–174 GB | 7.08–9.96 h | 83% |
| 7431373–375 (chain C, lcp 05/06) | 156–209 GB | 8.80–**11.36 h** | **95%** |

Batch-by-batch, since the peak is not evenly spread: 7431373 ran 9.74–11.32 h, 7431374 8.80–**11.36 h**, and 7431375 (complete 2026-09-15) only 9.11–10.02 h. So two of the three batches put a subjob within 40 minutes of the wall, and the third had two hours of room — the margin is real but it varies by batch rather than trending.

Peak memory (209.34 GB of 235, 7431375[7]) sits inside the 175–206 GB band forecast for chain C, so that prediction held. **Elapsed is the concern:** 11.36 h on 7431374[1] leaves 38 minutes of margin, against 1.24 h for chain A. Landscapes 05/06 behave like 01/02, not like the cheaper 03/04. The remaining batch 7431376 is only 8 lines on 2 nodes so it is the least exposed, but **any future round at these settings should treat 12 h as genuinely marginal** — and 12 h is effectively the cap, so the lever is splitting CSVs to one GCM per line (~3.6 h/line, 3× the lines, identical node-hours, better backfill), not a longer walltime.

**UCAR's two technical points: (1) is valid but deferred to the processing chain, (2) rests on a false premise.** (1) `afterokarray`: `launch_cf` builds an array whenever a cmdfile spans more than one node, and both submit scripts use plain `afterok`. PBS Pro wants the array form. NCAR's own job-dependencies page documents only `after{,ok,notok,any}` and never mentions arrays, which is how this was missed. Their advice needs one caveat: a cmdfile that fits on one node produces a **non-array** job (7349725 had no `[]`), so in general the clause must be *detected* rather than hard-coded. **Neither submit script needs that detection**, though, because every cmdfile they chain spans at least two nodes — the smallest is the 8-line scenario tail batch (2 nodes) and the 9-line spinup cmdfile (3 nodes). Only the processing jobs are single-node, and they are launched by hand, never chained. So the fix is an unconditional `array_dep` helper that normalises the captured ID to `<seq>[]`, which is the part a literal `afterok` → `afterokarray` swap would get wrong: the array form *requires* the brackets, and we still do not know whether `launch_cf`'s last stdout line prints them. Verified against all four plausible ID formats (`7240530`, `7240530[]`, `7240530.desched1`, `7240530[].desched1`).

**The helper lives here, not in the script.** It was drafted, tested against those four formats, and then removed from `submit_chain.sh` on 2026-09-15 rather than left sitting as dead code — both submit scripts now just point at this entry. To adopt it, paste this in and swap `-W depend=afterok:"${JID}"` for `-W depend="$(array_dep "$JID")"`:

```bash
array_dep() {
    local seq="${1%%.*}"      # drop the .desched1 server suffix
    seq="${seq%%\[*}"         # drop [] if launch_cf already printed it
    echo "afterokarray:${seq}[]"
}
```

**How `afterok` has actually behaved, for the record:** it has fired correctly on every dependency of chains A, B and C *except* the two stranded by the stuck array parent on 2026-09-08 — and that case is the only thing `afterokarray` would change. (An earlier version of this entry and of the script comments claimed "all twelve dependencies across chains A and B" fired; that was wrong on both counts, since A and B carried thirteen between them and two of A's did not fire. Corrected 2026-09-15.) (2) `-r n`: **UCAR's premise here is wrong, and so was the guess recorded earlier in this entry.** NCAR did flip the PBS default to non-rerunnable in June 2024 (arc.ucar.edu/articles/674), and that bulletin does say *"the array launching command launch_cf has been updated for this"* — which led both UCAR and this note to conclude we must be on a stale local copy, probably `/glade/work/benkirk/repos/NCAR-pbstools/bin/launch_cf`. The chain C submission disproves it. `launch_cf` resolves to the **system** tool, `/glade/u/apps/opt/pbstools/bin/launch_cf`, and that tool emits `-r y` in the qsub line itself:

```
qsub -v command_file=...,n_total_steps=32,max_start_delay=0 -r y -q main \
  -l select=1:ncpus=128:mpiprocs=4:ompthreads=16:mem=235GB -J 0-7 \
  -A UCIE0001 -l walltime=12:00:00 -l job_priority=economy .../launch_cf.pbs
```

So switching copies cannot fix it and there is nothing to pin.

**CLOSED 2026-09-15 — NCAR's ruling: do not add `-r n`.** Gary confirmed `-r y` is **hard-coded** in `launch_cf`, that the system default makes array jobs rerunnable anyway, and that passing `-r n` as well *"may be ill defined and would require further study to see how PBS reacts to it being included once with `y` and subsequently again with `n`."* His advice: *"I think you should leave it the way you have been running it."* He also thinks `Rerunable = True` may be what made 7240530 unkillable, though he is not certain. This retires the argument-order reasoning recorded above — it was plausible but is now moot, and both submit scripts carry a `DO NOT ADD -r n` comment so it does not get retried. **The clobber risk is therefore managed by process, not by a flag: if a job ever has to be cleared, tell NCAR to DELETE it, never requeue it**, because the runner has no resume guard.
**Why:** the batch collapse is the cheapest throughput change available and it rests on a measurement that only existed because two chains happened to overlap. Keeping it separate from the PBS-correctness work means a chain C failure can only be attributed to one of the two changes.

---

### 2026-09-15 — area_dom processing chain; concurrency is set by lines per cmdfile, not steps-per-node
**Context:** Chain C batches 1–2 verified complete by sentinel (`cmdfile_chC_01/02`: 96 expected, 96 complete, 0 partial, 0 missing each), so landscapes 01–05 have a full scenario set and area_dom post-processing can start; landscape 06 waits on 7431375/7431376. That is 780 processing lines, too much to submit in one go, so it needs a chain.
**Decision/Finding:** Batching went into **`generate_process_cmdfiles.sh`** and the new **`analysis-scripts/submit_chain_process.sh`** is a plain glob-and-chain loop — the same split the iLand tooling already uses, where `generate_cmdfiles.sh` chunks and `submit_chain.sh` only submits. A first attempt put the chunking inside the submitter instead, which needed env overrides, a count argument and a dry-run mode; it was rewritten because 130 lines of bash in the submission path is not maintainable. The submitter is now 41 executable lines against `submit_chain.sh`'s 36.

**Concurrency is set by the number of LINES in a cmdfile, not by `--steps-per-node`.** launch_cf submits one subjob per node and PBS can start them all at once, so every line in a cmdfile can be running simultaneously. Each line forks 9 workers for scenario, and **each worker opens its own SQLite connection** (`process_area_dom.R:50`, inside the parallel chunk function) and writes its own parquet (`:161`). So a whole landscape in one file — 156 lines, 13 nodes — would be ~1400 concurrent readers/writers on scratch, against the **90 that job 7349725 actually proved** (18 lines × 5 workers, one node). `--steps-per-node` only decides how many steps share a node, i.e. memory and cores per node. Hence `NODES_PER_JOB=3` in the generator: 36 lines, 3 nodes, ~320 concurrent workers, 3.6× proven. Scenario's 156 lines split 4 × 36 + 12, so **five batches per landscape and 25 for landscapes 01–05**.

**`--steps-per-node 18` does NOT transfer from spinup to scenario — it fails on core count alone.** `process_area_dom.R` sets `cpus <- min(nrow(chunks), 10)` over `seq(min_yr, max_yr, by = 10)`. Spinup writes only year ≥ 260, so 41 years is 5 chunks = 5 workers per step and 18 × 5 = 90 of 128 cores — which is why 18 is proven there. Scenario has **no year condition** on `stand`/`saplingdetail`, so all 86 years are written: 9 chunks = **9 workers per step**, and 18 × 9 = 162 on 128 cores, oversubscribed by 27%. The cap is ~14 steps/node. Both the generator and the submitter set **12** for scenario and must stay in step.

**Operating it:** `bash analysis-scripts/submit_chain_process.sh area_dom scenario`. Only one batch runs at a time, so **the first batch is measurable on its own by construction** — read `qhist -j <first jobid>` for mem/node and elapsed, and `qdel` the held successors if it looks wrong. That is why the submitter needs no dry-run or count argument. Per-step memory is **unmeasured** for scenario processing: the spinup managed ~10 GB/step over 41 output years and 86 years is roughly double the table volume, so 10–20 GB/step is plausible, and at 12 steps/node that is 144–240 GB against a 235 GB request — the top of the range does not fit. If it lands near 20 GB/step, drop `--steps-per-node` in **both** files. Re-running a processing batch is **safe**, unlike the model chains: it reads model output and writes a `processed/` tree, so a repeat recomputes rather than destroying anything.

**Two details that avoid future traps.** The generator clears only *the landscape being regenerated* (`cmdfile_<analysis>_<kind>_<NN>_b*.sh` plus the old un-suffixed name), never the whole directory, so generating landscape 06 later cannot delete 01–05's batches. And batch numbers are zero-padded (`_b01`), because at a smaller batch size a landscape would exceed nine batches and `_b10` would sort before `_b2`. Verified lossless: the 780 lines pooled from the batch files sort byte-identical to the pre-change per-landscape files.

**SUBMITTED 2026-09-15 as 7477443–7477467**, 25 batches, consecutive, landscapes 01–05 in order, first `Q` and the other 24 `H`. Per node: `select=1:ncpus=128:mpiprocs=12:ompthreads=9:mem=235GB`, walltime 2 h. The b01–b04 batches are 3 nodes (`-J 0-2`); b05 of each landscape is the 12-line tail.

**And that tail batch turned out to matter for the `afterokarray` question.** 12 lines at 12 steps/node is *exactly one node*, so launch_cf submits it with **no `-J` and an ID with no brackets** — `7477447.desched1`, not `7477443[].desched1`. The chain therefore runs `…7477446[] → 7477447 → 7477448[]…`: a plain job depending on an array, and an array depending on a plain job, **five times over**. `afterokarray` is rejected on a non-array predecessor, so **the unconditional `array_dep` helper would have broken this chain at every b05.** The trap was recorded earlier as "if scenario and spinup processing are ever chained together" — that framing was too narrow; it bites inside a single chain, from the ragged tail batch alone. If `afterokarray` is ever adopted here it must detect per predecessor with `qstat -xf "$JID" | grep -qiE '^[[:space:]]*array[[:space:]]*=[[:space:]]*True'`. Plain `afterok` accepts both forms, which is what the chain uses and why it queued cleanly. The two *model* submit scripts remain all-array — their smallest cmdfile is 8 lines on 2 nodes — so the switch stays viable there.

**MEASURED 2026-09-16 on 7477443–7477446 (landscape 01, b01–b04) — per-step memory was OVERESTIMATED and cores are the real cap.**

| | measured |
|---|---|
| per node (12 steps) | 103.43 – 120.68 GB of 235 — **44–51% of the request** |
| per step | **8.62 – 10.06 GB** |
| elapsed | **0.44 – 0.68 h** (26–41 min) of a 2 h walltime |

(Range extended 2026-09-16 to cover 7477447 and 7477448. Notably **7477447, the single-node non-array b05 batch, is the highest at 120.68 GB** — same 12 steps as any other node, so nothing about being a plain job changes its footprint.)

The pre-run estimate was 10–20 GB/step, on the reasoning that scenario processing holds 9 year-chunks against the spinup's 5 and would therefore need more memory per step. **It does not** — scenario per-step memory is effectively identical to the spinup's ~10 GB, so the extra chunks cost time and cores rather than resident memory. The `cmdfile_process_area_dom.sh` header carried the same prediction ("per-step memory will exceed 10 GB by an unmeasured amount"); corrected there too. **The binding constraint is cores, exactly as the sizing note said: 12 steps × 9 workers = 108 of 128, capping this at ~14 steps/node.** Memory has ~116 GB of headroom.

**The chain is QUEUE-WAIT dominated, but the wait is BETWEEN batches, not inside them.** Deriving start times as end − elapsed, the three subjobs of a batch start within minutes of each other — 6 min apart for 7477444, 2 min for 7477445, 22 min for 7477446. **The only wide spread is inside 7477443, and it is `[0]` running *early*:** it backfilled at 15-17:54 immediately after submission while `[1]` and `[2]` waited for the overnight window at 16-00:14. That is a first-batch artifact of submitting mid-afternoon, not the steady-state behaviour.

The real cost is the gap from one batch finishing to the next one starting — and it **tracks time of day rather than being a constant**: 7 min, 76 min and 78 min across the overnight transitions, then **~0 min and ~0 min** in the morning (7477447 started the instant 7477446 ended, and 7477448 the instant 7477447 ended). So the 25-batch chain lands somewhere between **~17 h** if gaps stay near zero and **~3 days** at the overnight rate; the three-day figure is the pessimistic end, not the expectation.

Two consequences. **(1) 324 concurrent workers is PROVEN, not merely bounded.** Since a batch's three nodes overlap almost entirely, all 36 lines really do run together — four batches, no I/O errors, memory at 44–51%. *(An earlier version of this entry claimed the opposite — that staggered subjobs meant real peaks of only 108–216 workers, so the I/O cap went untested. That was wrong: it generalised from 7477443 alone. Corrected 2026-09-16.)* Raising `NODES_PER_JOB` is therefore justified by evidence rather than optimism. **(2) Walltime should be 1 h, not 2 h** — the worst batch used 41 minutes, so 1 h leaves ~19 minutes of margin and backfills sooner, which is what the original hand-written `cmdfile_process_area_dom.sh` invocation used. Both are one-line changes (`NODES_PER_JOB` in the generator, `-l walltime=` in the submitter) and neither was made mid-chain.

**Gap worth knowing:** `check_cmdfile_complete.sh` does **not** work on processing cmdfiles. It parses the iLand runner signature (xml, start_rep, end_rep, years, csv); a processing line is `... Rscript process_<analysis>.R "<landscape>" "<treatment>" <rep>`. Completeness of processing output needs its own check, not yet written.
**Why:** the 18-vs-12 question would otherwise have been settled by analogy with the spinup, which the cores cannot absorb; and the lines-vs-steps distinction is what actually controls the disk I/O risk the chain exists to manage.

---

### 2026-11-16 — Re-audit of the NorEsm2-MM/ssp245 source files: all three STILL broken, and CPCRW holds good copies
**Context:** Asked whether the source `.nc` files had been re-exported, i.e. whether re-running scripts 03 and 04 would now fix the databases. Re-ran the audit's own tests against the share from a machine that can see `Z:/project_data/downscaling/`.

**Answer: nothing has been re-exported. All three files are unchanged.**

| file | mtime | size | CRS | data |
|---|---|---|---|---|
| `tasmin-1958.nc` | 2026-03-09 18:12 | **48,420 B** (stub) | **EMPTY** | 0 readable values |
| `vp-1958.nc` | 2026-03-12 14:56 | 6.42 GB | ok | **0 non-NA in the entire layer**; 0 of 930 cells over the lcp02 extent |
| `vp-2066.nc` | **2024-11-15 07:46** | 6.42 GB | **EMPTY** | NA mask gone (**3,972,314** non-NA vs 916,466 for healthy years) |

`vp-2066` has not been touched since the original November 2024 export. And `project(ext(env), to = crs(r))` — the call at script 03 line 104 — still throws `[project] output crs is not valid` for `tasmin-1958` and `vp-2066`, exactly as before.

**Swept the whole combination:** all 755 files (5 variables × 151 years) checked for empty CRS and stub size. **Only those two.** No new defects of that class. *Caveat: this sweep cannot catch the `vp-1958` class — valid CRS, correct size, all-NA content — without reading a layer from every file (~13 GB over the share). Script 04's NA guard catches that class at compile time instead.*

**Refinement to the audit PDF's wording.** It describes `vp-2066` as "Every value 0". Measured: over the lcp02 extent every cell is a **constant 5.302e-05**, not literally zero, and **no cell anywhere in layer 1 is exactly 0** (healthy 2065 over the same cells reads 1.033–1.223). Physically that is indistinguishable from zero vapour pressure and would round to 0.00 at script 04's 2 dp, so no conclusion changes — but "a constant 5.3e-05 with the NA mask destroyed" is the more exact and more diagnostic description if that document goes back to the data producer.

**NEW AND USEFUL: the CPCRW tree holds intact copies of all three.**

| CPCRW file | CRS | non-NA | range |
|---|---|---|---|
| `vp-1958` | ok | 3249/3249 | 1.015–1.428 |
| `vp-2066` | ok | 3249/3249 | 1.078–1.631 |
| `tasmin-1958` | ok | 3249/3249 | 249–253.1 K |

So **landscape 01's data exists and is fine** — the pipeline simply cannot reach it, because `project()` throws on the Landscapes file before the fallback test on line 106 is ever evaluated.

**The built databases confirm it — queried directly 2026-11-16, lcp01 and lcp02 are IDENTICAL in defect.** Probing one climate table from each `NorEsm2-MMssp245.sqlite` (lcp01 has 736 tables, lcp02 has 676), for years 1957–1959 and 2065–2067:

| year | NULL `min_temp` | NULL `vpd` | other columns |
|---|---|---|---|
| 1958 | **365** | **365** | clean |
| 2066 | 0 | **365** | clean |
| 1957, 1959, 2065, 2067 | 0 | 0 | clean |

Both tables span 1950–2100. **So landscape 01's one win from CPCRW — a good `vp-1958` — is invisible in the database**, because `vpd = es(tasmin, tasmax) − vp` and its `tasmin` 1958 is missing anyway. **In practice lcp01 is in exactly the same state as 02–06: no difference at all.** The source data for lcp01 is good and the processed tables are not; the whole gap is the code path.

**Can scripts 03 + 04 be re-run to fix the databases? No, not as the code stands.** Script 03 would fail on the same two files (loudly now, thanks to the October `warning()`), and script 04's year-set and NA guards would then refuse to write. That refusal is the guard working, not a new fault.

**Landscape 01 alone could be fixed by code**, by routing an empty CRS to CPCRW rather than letting `project()` throw. Two cautions before anyone does that: (1) a naive "empty CRS → use CPCRW" is **wrong for landscapes 02–06**, which CPCRW does not cover — the crop would be all-NA and script 03 would write a file of NAs, downgrading a loud failure to one only script 04 catches; it would need a coverage check that fails loudly otherwise. (2) It would leave lcp01 with real 2066 data while 02–06 are still missing it, an inconsistency *across* landscapes within the same scenario comparison, which may be worse for the science than all six being affected the same way. **Science call, not a code call.**

---

### 2026-11-16 — How to check processing output for completeness: count parquet, not replicates
**Context:** The long-standing TODO "a completeness checker for *processing* output" — `check_cmdfile_complete.sh` parses the iLand runner signature and does not work on processing cmdfiles. There is now an exact arithmetic check, and it reconciled to zero on the first try.

**The unit is the parquet file, not the replicate.** `process_area_dom.R` chunks years with `span = 10` and writes one `chunk_<start>_area_dom.parquet` per chunk (line ~163). So **a 2015–2100 scenario replicate writes 9** (`seq(2015, 2100, by = 10)`), and **a spinup replicate writes 5**. Expecting "1170 parquet" for a 1170-run round is wrong by a factor of 9.

```
find /glade/derecho/scratch/qasena/output_ak_can -path '*/area_dom/*.parquet' | wc -l
```

**Reconciled 2026-11-16 — 19,224, exactly, no residual:**

| | replicates | × chunks | parquet |
|---|---|---|---|
| scenario, fri 60/120 (September) | 936 | 9 | 8,424 |
| scenario, fri 10/15/30 (this round) | 1,170 | 9 | 10,530 |
| spinup, 6 landscapes × 9 reps, 1 treatment | 54 | 5 | 270 |
| **total** | | | **19,224** |

**Note the `find` is landscape-wide and counts every round ever processed**, scenario and spinup together, so the expected figure must be built the same way — cumulatively — rather than from the round just submitted. The spinup contribution is easy to forget: `cmdfile_area_dom_spinup_NN_b01.sh` is 9 lines, one treatment (`NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120`) × reps 1–9, for each of the 6 landscapes.
**Why it is a real check:** an exact match with zero residual says both that nothing is missing and that nothing stray is present — stronger than a lower-bound count.

**The KBDI gather is self-checking in the same spirit.** Re-running it on 2026-11-16 reported `gathered: 0, already present: 2106, wrong KBDI count: 0, failed: 0`. **That is what closes the truncated-tarball worry**, and the reasoning matters: the re-run itself cannot detect truncation, because the resume guard tests whether `kbdi.tar.gz` *exists*, not whether it is intact. What rules a mid-`tar` kill out is that **0 were gathered** — a kill partway would have left every later replicate ungathered. `gzip -t` across the archives remains worthwhile as insurance before transferring off Derecho, but it is no longer a live concern.

---

### 2026-11-16 — The area_dom chain finished in 32 h; 1 h walltime vindicated, and the nodes are NOT core-bound
**Context:** All 36 batches (8176545–8176580) ran to completion over 13–14 November. `afterok` released 35 times without a stall. Structure confirmed from `qhist`: **102 nodes = 30 batches × 3 + 6 batches × 2**, the six 2-node jobs being exactly the `b06` tails (15 lines at 12 steps/node).

**Measured, 102 nodes at 324 concurrent workers:**

| | measured | against |
|---|---|---|
| batch wall (max of its nodes) | **0.27–0.66 h**, mean 0.46 h | 1 h request |
| worst single node | **40 min = 66% of the wall** | ≈20 min margin |
| memory | 65–112 GB, peak **48%** | 235 GB |
| CPU utilisation | **20–41%, mean 32%** | 128 cores |

**The 1 h walltime was right, and 2 h would have been dead weight.** The worst batch used 40 of 60 minutes — almost exactly September's 41 min at the same concurrency, which is a clean reproduction a round later. Nothing came close to the wall.

**324 workers reproduced September exactly.** Reverting `NODES_PER_JOB` 6 → 3 cost nothing measurable: same per-batch elapsed, same memory profile. The proven setting stayed proven.

**CORRECTION TO THE 2026-09-16 ENTRY: the nodes are not core-bound.** That entry inferred "cores are the cap, ceiling ~14 steps/node" from the arithmetic 12 steps × 9 workers = 108 of 128 cores. The measurement says otherwise — **mean CPU utilisation is 32%, never above 41%**, so the 108 forked workers are nowhere near saturating 128 cores. They are **I/O-bound on Lustre**, not compute-bound. Memory tells the same story at 48% of the request.

**What that does and does not imply.** Headroom on both cores and memory means `--steps-per-node` *could* go above 12 — but it does not follow that throughput would improve, because the limiting resource is the filesystem, which more steps per node would contend for harder, not less. Treat this as a correction to the *diagnosis*, not a licence to raise the dial. If it is ever worth testing, the honest experiment is one batch at a higher `spn` with elapsed compared like for like.

**Wall-clock: 31.8 h for 36 batches, ~53 min per cycle, 48% queueing.** Compute averaged 28 min per batch, queue wait ~25 min, with gaps of 25–159 min (median 35). **My estimate of 2.5–4.5 days was too pessimistic** — it extrapolated September's ~2.9 h cycle, which was measured at *economy*. Premium roughly halved the queueing (48% here against ~80% then). For planning: **at premium a 36-batch processing chain is a ~1.5-day job, not a 3-day one.**

---

### 2026-11-13 — area_dom submitted on UCEM0001; concurrency reverted to the proven 324; the round is verified complete
**Context:** Resuming after the UCIE0001 expiry. Three things settled: the new allocation, the batch size, and — unexpectedly — whether the 1170 model runs actually finished.

**New allocation `UCEM0001`.** Substituted for the expired `UCIE0001` in all three submit scripts: `analysis-scripts/submit_chain_process.sh`, `scenario-launch/submit_chain.sh`, `spin-up-launch/submit_chain_spinup.sh`. UCIE0001 is dead — it can now only return `Account is in state: Expired`. Editing all three at once is deliberate: the NorEsm2-MM re-runs will need the model submitters, and a stale ID there fails at submission rather than quietly.

**`NODES_PER_JOB` 6 → 3, reverted.** Back to 36 lines per batch = **324 concurrent workers**, the setting proven on 2026-09-16. The raise to 6 (648 workers) was bought on 2 November against what looked like a closing allocation window; with that pressure gone there is no reason to spend a known-good setting on an untested one. **The general rule, and it is the user's:** a longer chain costs **wall-clock, not allocation**, so when there is time to let it queue, more batches is the cheap side of the trade. 648 remains untested — it ran once on 2026-09-17 with the outcome unrecorded and `qhist` has since aged out. Turn that dial only when a round is deadline-bound, and capture `qhist` + `step-*.out` on the first batch if so.

**Regenerated: 36 cmdfiles, 1170 lines**, six batches per landscape (5 × 36 + 15), 0 blanks, verified **lossless** against the committed 18-file version — identical command set, only regrouped. Every batch is ≥ 2 nodes, so all are arrays; none of the single-node plain-job tails that complicated the September `afterokarray` question.

**Submitted: 8176545–8176580**, 36 batches, first `Q` and 35 `H`. **These IDs are consecutive**, unlike 7884487–7884503 where two IDs went to other users mid-chain — so the mapping is six per landscape in sorted glob order (01 = 8176545–50 … 06 = 8176575–80). That is inferred from the consecutive block plus the glob order; consecutiveness is a property of this submission, not a rule.

**No `| tee` on a processing submission, and the reasoning generalises.** The habit comes from the model chains, where a job runs for days, IDs are not consecutive, and losing the job→cmdfile mapping is expensive. None of it applies here: the submitter already echoes each job ID, `stdout-<jobid>.*` names the landscape and treatment per step, and a processing batch is cheap to re-run. The companion `2>&1` exists only because `launch_cf` writes diagnostics to stderr, which is not worth capturing for this.

**THE ROUND IS VERIFIED COMPLETE — and `gather_fire_kbdi.R` is the better check.** Its inventory found **2106 replicates, every one with 86 KBDI grids**, a single-valued distribution with no odd counts. 2106 = 936 (fri 60/120, September) + 1170 (fri 10/15/30). This **supersedes running `check_cmdfile_complete.sh` over the 15 `cmdfile_chA_*.sh`**: the `.complete` sentinel says a run exited cleanly, whereas a full set of 86 annual grids says it actually reached 2100. Worth reusing — the gather's inventory is a free completeness audit of the whole scenario round, and it needs no allocation.

**One live risk while the gather runs on a login node.** If it is killed mid-`tar`, the resume guard will skip the truncated archive on the next run, because it tests whether `kbdi.tar.gz` **exists**, not whether it is intact. A kill is otherwise free. Before transferring anything off Derecho:
```
find /glade/derecho/scratch/qasena/output_ak_can -name kbdi.tar.gz   | while read f; do gzip -t "$f" 2>/dev/null || echo "CORRUPT: $f"; done
```
The proper fix is to tar to a temp name and rename on success; not applied here because the script was already running.

---

### 2026-11-02 — Processing the short-FRI round: `--fri` scoping, 6 nodes per batch, 1 h walltime, premium
**Context:** The fri 10/15/30 round finished on 1 November with 1170 runs across 30 new treatments. `generate_process_cmdfiles.sh` globs every scenario CSV, so an unscoped run would have emitted 54 treatments — the 30 new ones plus the 24 fri60/120 ones already processed in September.
**Changes:**
- **`--fri "10 15 30"`** scopes the generator to one round. It filters the **CSV glob**, not the assembled treatment names, because a treatment can carry an optional `id` suffix *after* the fri token (`..._fri10_<id>`) which would defeat a `grep _fri10$`. Omitting `--fri` keeps the original behaviour of emitting every round.
- **`--landscapes` is now validated** — two digits, and a matching `landscape_alaska_NN` directory must exist. The `--landscapes bash` typo of 2026-09-17 silently produced a full set of cmdfiles addressed to `landscape_alaska_bash_...`, which look perfectly normal until every step fails on Derecho.
- **`NODES_PER_JOB` 3 → 6, scenario only.** Spinup stays at 3; its processing is finished and there was no reason to disturb it.
- **`submit_chain_process.sh`: walltime 2 h → 1 h, `job_priority` economy → premium.**

**On the walltime.** 1 h is what the original hand-written `cmdfile_process_*.sh` invocations used at 9 and 18 steps/node. The 2 h this submitter shipped with on 2026-09-15 was never backed by a measurement, and the 2026-09-16 entry above had already concluded it should be 1 h on measured margin — the worst batch used **41 minutes**, so 1 h leaves ~19 min. That reasoning rests on margin, not on the walltime-backfill hypothesis retracted on 27 October, so the retraction does not void it.

**648 concurrent workers is a test, not a confirmed setting.** What is proven is 324 (2026-09-16 entry: four batches at 36 lines, no I/O errors, memory 44–51%). 648 ran once, on 2026-09-17, when the lcp05 and lcp06 chains overlapped — but that outcome was never written down and Derecho's `qhist` has since aged out, so the evidence is recollection plus the absence of any recorded failure. Acceptable because **failure here is cheap**: a processing step only overwrites its own parquet, so a stall costs one `submit_chain_process.sh area_dom scenario <start_batch>` and no primary data. The two risks share one check — if the first batch lands near 50 min, both the walltime and the concurrency are too aggressive. **Capture `qhist -j <first jobid>` and the first batch's `step-*.out` this time**: September's evidence evaporated for want of that, which is the same lesson as "always keep the submit echo".

**Generated:** 18 cmdfiles, 1170 lines, 3 batches per landscape (72/72/51), 0 blanks, 390 lines per fri value, 180 `onlysimfalse` + 15 `onlysimtrue` lines per landscape. `git status` shows 18 modified and 12 deleted, because the new set is 3 batches per landscape against the old 5.

**fire/KBDI needed no changes at all.** `gather_fire_kbdi.R` discovers treatments by listing directories on scratch rather than reading the CSVs, so the new treatments appear automatically, and it skips any replicate whose fire CSV and KBDI archive both already exist — so re-running it picks up only the new 1170. It runs on a login node with no allocation, which is why it goes first while the allocation position is uncertain.

---

### 2026-11-02 — The fri round completed in full; held jobs ran past the allocation end date
**Context:** The 15-batch chain (7884487–7884503) was expected to lose batches 14 and 15 to the 31 October end of UCIE0001 — see the superseded entry below.
**What happened:** All 15 batches ran. `7884503` **started 1 November ~08:53 and finished 19:18**, so a job still held in the queue at the allocation's end date was dispatched afterwards and ran to completion. The round is done: 468 lines, 1170 model runs, landscapes 01–06 at fri 10/15/30. No mop-up and no second project ID were needed.
**Correction:** the 29 October plan assumed queued jobs would stop being eligible to start at the project end. That was flagged as an inference at the time, and it was wrong. **Mechanism now confirmed, 2026-11-02:** a submission attempt returned `qsub: Account is in state: Expired`, listing `UCIE0001, Expired, True`. The rule is that **a queued job keeps its eligibility and runs to completion, but no new job can be submitted after the end date** — there is no submission grace period. Plan the next deadline around getting everything *queued* before the end, not around finishing before it.
**The 16 h walltime extension was load-bearing, by about one minute.** `7884500[2]`, an lcp05 ssp370 `onlysim=true` line, ran **12.02 h**. At the default 12 h cap it would have been killed, its array subjob would have gone non-zero, `afterok` would never have fired, and batches 13–15 would have stayed held indefinitely. `7884501[1]` (lcp05 ssp370 simtrue, fri30) came in at 11.74 h — inside 12 h by 16 minutes.
**For future rounds: lcp05 ssp370 `onlysim=true` does not fit a 12 h walltime.** Request 16 h up front, or split those CSVs to one GCM per line (~4 h each, same node-hours, better backfill). It is the only configuration that has ever exceeded 12 h; everything else peaked at 11.52 h.
**Prediction method validated on all six landscapes.** `fri60 baseline × 1.043` predicted the fri10 cost within ~1.5% everywhere: lcp02 8.89/8.66–8.89, lcp04 9.78/9.79, lcp03 10.34/10.41, lcp06 10.45/10.52, lcp01 11.51/11.52, lcp05 11.84/12.02. lcp05 is the only landscape that came in above prediction.
**Queue gaps closed the round at 8.2, 9.2 and 7.3 h**, shorter than the 10–22 h of late October — consistent with cluster load rather than anything about the jobs, as the retracted walltime-backfill hypothesis already concluded.

---

### 2026-10-29 — The fri round will not finish inside the UCIE0001 allocation; mop-up is chA_14 + chA_15
**SUPERSEDED 2026-11-02 — no mop-up was needed; the chain completed in full. Kept for the serial-vs-parallel reasoning and the resume runbook, which is still the correct procedure if a chain is ever cut short.**
**Context:** The single 15-batch chain (7884487–7884503) submitted 2026-10-20 is 10 batches in. Queue wait, not run time, set the pace throughout: gaps between batches ran 0.95–22.7 h with no relationship to the walltime requested, and the project ends 31 October.
**Finding:** Batches 11–13 should complete under UCIE0001; **batches 14 and 15 will not start in time.** Both are entirely `landscape_alaska_06` (52 lines), so the break falls on a clean landscape boundary with no partial-landscape bookkeeping.
**To resume on a new project ID:**
1. Edit `-A UCIE0001` in `scenario-launch/submit_chain.sh` — it is hard-coded there, and likewise in `submit_chain_spinup.sh` and `analysis-scripts/submit_chain_process.sh`.
2. Confirm what actually landed: `bash analysis-scripts/check_cmdfile_complete.sh scenario-launch/cmdfile_chA_13.sh` — it tests the `.complete` sentinel, which is proof; line arithmetic is not.
3. `bash scenario-launch/submit_chain.sh A 14`. The existing `cmdfile_chA_*.sh` are reusable as-is and nothing needs regenerating. The batch you start *from* is re-run in full, so start at the first batch that did not complete.
**Walltime:** the mop-up does **not** need an admin raise. Both batches' slowest lines are lcp06 ssp370 `onlysim=true` at ~10.45 h, inside the default 12 h cap. Only lcp05 (chA_12/13) needed the 16 h UCAR granted, and those run before the cut.
**Why not parallelise instead:** splitting the tail into independent chains would have landed ~30 October, but at 64–96 concurrent models against a measured-safe 32, with untested disk-I/O risk and added contention on the lcp05 lines that already project to 11.84 h of a 12 h wall. Having a fallback allocation makes the serial path the better trade.

---

### 2026-10-23 — Measured per-run costs, and how cmdfiles should be packed in future
**Context:** The fri 10/15/30 round produced per-step timings across several landscapes and every fire configuration, which is the first dataset good enough to reason about cmdfile packing properly. Recorded for future rounds; **nothing was changed while the chain was running.**

**The structural fact everything follows from: a node's `--steps-per-node` steps run CONCURRENTLY, not sequentially.** So a node's elapsed time is the **max** of its steps, and a batch's wall time is the max over all its steps. A step is one cmdfile line, and its duration is the **sum** of its CSV's rows, which run sequentially inside the step.

Two separate consequences, often confused:

**1. For WALL TIME, the only lever is rows per CSV.** Node packing is irrelevant — the batch cannot finish before its longest single line. The longest lines this round were the `onlysim=true` ones at 3 rows × ~3.8 h = **11.52 h**, which is what forced the 16 h walltime extension. Splitting just the simtrue CSVs to 1–2 rows would have capped every line near **9 h** (ssp370 fri30 simfalse, 3 × ~3.0 h, becomes the new longest) and made the extension unnecessary.

**2. For NODE-HOURS, cluster slow with slow — do NOT mix fast with slow.** Mixing is actively counterproductive: four slow steps on one node and four fast on another costs 11.5 + 6 = 17.5 node-hours, where spreading them one-per-node costs 2 × 11.5 = 23. Measured on batch 2: 214.5 step-hours of work consumed **61.2 node-hours against an ideal of 53.6 — 12% wasted** on imbalance. The current line ordering causes this almost perfectly badly: each landscape's 6 simtrue lines sit at positions 13, 26, 39, 52, 65 and 78 of its 78-line block, so at 4 steps/node they reliably land one per node, each stranding three idle slots for ~5 h.

**What can and cannot be mixed in one CSV.** The runner reads `fri` and `onlysim` from each row individually (`modules.fire.fireReturnInterval=${fri}`, `modules.fire.onlySimulation=${onlysim}`), so a CSV mixing fri values works today with no code change. **But simtrue and simfalse rows cannot share a CSV:** `start_rep`/`end_rep` are line arguments applied to every row, so a mixed CSV run for reps 1–12 would produce 12 replicates of the simtrue row, which is meant to have exactly 1.

**Measured cost per model run** — the basis for any future packing. It depends on landscape, fri and onlysim, and **barely on SSP**: lcp02 ssp245 fri10 is 1.35–1.43 h/run against ssp370 fri10 at 1.38–1.42. So "ssp245 lines are two-thirds the work" is entirely a row-count effect (2 GCM rows vs 3), not a per-run one.

| configuration | lcp01 | lcp02 |
|---|---|---|
| fri10 simfalse | 2.02 | 1.35–1.43 |
| fri15 simfalse | 2.45 | 1.69–1.89 |
| fri30 simfalse | 2.90–3.02 | 2.04–2.23 |
| **simTRUE, any fri** | **3.71–3.84** | **2.89–2.96** |

Two patterns hold across both landscapes. **More fire makes a run faster** — mortality cuts the tree count that growth, pattern and seed dispersal all scale with — monotonically from fri10 to fri30. And **`onlysim=true` costs ~3.7–3.8 h/run on lcp01 regardless of fri**, because fire never kills anything, so it is effectively a no-fire run; it matches the previous round's fri60/120 peak of 3.79 h/run.

**Landscapes differ by ~30%, and only lcp01 is expensive** — lcp02 runs at 0.69–0.77× lcp01 on every configuration. Last round's chain A combined 01 and 02 in one chain, so this was invisible; one landscape per batch separates them cleanly. First lcp03 datapoint is ~1.25× lcp02.

**If the generator is revisited:** split the simtrue CSVs (caps lines near 9 h, biggest win, smallest change), and emit each landscape's 6 simtrue lines **together** rather than one per fri-group, which clusters them onto shared nodes and recovers most of the 12%. Both preserve the sequential-by-landscape ordering that makes outputs readable as they appear.
**Why:** 12% of allocation and a walltime extension were both avoidable, and the data to avoid them next time only exists because this round ran one landscape per batch.

---

### 2026-10-20 — NorEsm2-MM out of ssp245, premium priority, and one chain instead of three
**Context:** Ten days left in the project timeline, the fri 10/15/30 round still unsubmitted, and the NorEsm2-MM/ssp245 climate known corrupt (2026-10-16 entry).
**Decision/Finding:** **NorEsm2-MM is excluded from ssp245 alone**, by deleting its row from the six `iland_scenarios_ssp245_sim{false,true}_fri{10,15,30}.csv` files. TaiESM1 and UKESM1-0-LL under ssp245 are clean and are kept; all of ssp370 keeps all three GCMs. Priority went `economy` → `premium` in `submit_chain.sh`.

**A first attempt dropped ssp245 wholesale and was wrong** — it discarded two good GCMs and the entire SSP contrast to remove one bad one. The reason the blunt version looked necessary is worth recording: a cmdfile line loops **every row of its CSV**, so the GCM set is a property of the CSV, not of the line. Excluding one GCM from one SSP therefore means editing those CSVs, not the generator. Once that was seen, the targeted fix was six `grep -v` edits.

**Scale: 468 lines, 1170 model runs** — and the run count is no longer 3× the line count. ssp370 lines loop three CSV rows, ssp245 lines two: 234 × 3 + 234 × 2 = 1170. The generator used to print `total * 3`, which would now be wrong by 234 runs, so it **counts each CSV's GCM rows instead of assuming three**. The same stale-multiplier assumption is what the climate guards were added to prevent a fortnight ago.

**Two side effects of keeping ssp245, both good.** The chain is back to 156 lines → **5 batches of 32/32/32/32/28**, which divides cleanly by `STEPS_PER_NODE=4`, so the under-fill warning the ssp370-only variant produced is gone (78 is not a multiple of 4; 156 is). And an ssp245 line is now about two thirds the work — roughly 5–7 h against 8–11 h — so **half the round has a wider margin against the 12 h walltime** than the fri 60/120 round did. That matters because chain C previously peaked at 95% of walltime.

**Premium is deliberately temporary.** It charges 1.5× against the allocation, bought to cut queue wait with the deadline close, and the allocation has the hours. It is the right lever rather than more packing: the 2026-09-16 timing study showed these chains are **queue-wait dominated** (gaps of 7, 76 and 78 minutes between batches against ~35 minutes of compute). **Drop back to economy once the deadline passes.** Only `scenario-launch/submit_chain.sh` changed — `submit_chain_spinup.sh` and `analysis-scripts/submit_chain_process.sh` are still economy, so this round's area_dom processing will queue at the old priority unless raised.

**Then collapsed to ONE CHAIN, one submission.** `CHAINS="A"` and `chain_landscapes A` now returns all six landscapes, so the round is a single 468-line chain of **15 batches (14 × 32 + 20)** rather than three chains of five. Total time is **unchanged** — one chain of 15 batches and three chains of 5 run back-to-back are the same ~141 h of compute; merging only removes the two manual handoffs.

**The split had a real rationale that premium retired.** At `economy` the queue wait was long enough that submitting the next chain while the current one ran meant it arrived roughly as that one finished — accidental staggering that held concurrency near 32 with nobody managing it. At `premium` that feedback is gone: submitting chain B while A ran would give 64 concurrent models, not a handoff. So the choice became *deliberately wait and submit by hand* versus *one self-sequencing chain*, and the second won.

**What that trades away, recorded so it is a known cost:** a stall now strands everything behind it — the 2026-09-08 stuck array parent stranded 2 batches, here it could strand up to 14, which makes `start_batch` more important, not less. And there is no longer a clean way to add parallelism mid-flight; with separate chains a second could be submitted alongside the first (disjoint landscapes, no shared source directories), whereas within one chain `start_batch` would re-run batches the running stream will reach. Restoring the split is two lines: the three-way `case` and `CHAINS="A B C"`.

Verified after regeneration: **lossless against the committed three-chain version** — the 468 command lines sorted are byte-identical, only the grouping moved; all 12 fri10/15/30 CSVs referenced with no fri60/120 leakage; **NorEsm2-MM in 6 of 6 ssp370 CSVs and 0 of 6 ssp245**; the fri 60/120 CSVs untouched and still carrying three GCMs; 15 cmdfiles, 468 lines, zero blanks, every batch divisible by 4, 432 simfalse / 36 simtrue. Batch numbers now reach `_15`, the first time the model chain has exceeded nine — the generator's `%02d` keeps the submitter's lexical glob in order across 09 → 10, which was checked rather than assumed.
**Why:** removing a whole SSP to avoid one GCM traded away more science than the defect cost. The CSV-per-line structure made the targeted fix cheap once it was recognised.

---

### 2026-10-16 — Three corrupt NorEsm2-MM/ssp245 climate files, and guards so the next ones are loud
**Context:** `NorEsm2-MMssp245.sqlite` had `min_temp` NULL for all 365 days of 1958 and `vpd` NULL for all 365 days of 1958 and 2066, identically in every climate table and all six landscapes. ssp370, TaiESM1 and UKESM1-0-LL were clean.
**Decision/Finding:** **Source data, not the pipeline — but the pipeline is why it was invisible for months.** Three defective `.nc` files, all under `Landscapes/Downscaled NorEsm2-MM/ssp245/`:

| file | size | CRS | contents |
|---|---|---|---|
| `tasmin-1958.nc` | **48 KB** (neighbours 6.4 GB) | **missing** | header only, no data |
| `vp-2066.nc` | 6.4 GB, correct dims/extent | **missing** | **every value 0, NA mask gone** |
| `vp-1958.nc` | 6.4 GB | valid | **all-NA over the Landscapes domain** |

All 151 yearly files exist for every variable, so any count- or size-based check passes — which is why the 2026-08-18 audit, which checked year *coverage*, missed it. `vp-2066` is **not recoverable locally**: the same cell block reads 0.854–1.44 in 2065 and 0–0 in 2066, i.e. a fully written but empty export. `vp-1958` is intact in the `CPCRW` tree, which is why landscape 01 alone escapes that one.

**The failure chain.** A missing CRS makes `project(ext(env), to = crs(r))` fail in script 03; the body is wrapped in `tryCatch(..., error = function(e) log_msg("ERROR", ...))`, and at the default `logs = FALSE` `log_msg` is `invisible(NULL)` — so **a failure was indistinguishable from a success**: no file, no message, exit status 0. Script 04 then left-joins the variables onto `tasmax`, which was complete, so a missing year became a **NULL column on a present row** rather than a missing row. And `vpd = es(tasmin, tasmax) − vp`, so vpd dies if *either* input does — hence 1958 losing both fields and 2066 losing only vpd.

**Scope, audited:** all 54 combinations (6 landscapes × 3 GCMs × 3 SSPs) were checked for variables disagreeing on their year set. **Only NorEsm2-MM/ssp245 is affected.** Landscapes 02–06 are short `tasmin` 1958 and `vp` 1958+2066. **Landscape 01 escapes exactly one of the three files — `vp-1958`, via the CPCRW fallback — and nothing else.**

*(Corrected 2026-11-16 against the audit PDF `Corrupt downscaled climate files — NorEsm2-MM ssp245.pdf`, which is the authoritative record: "min_temp is absent for all 365 days of 1958, and vpd for all 365 days of 1958 and 2066, **in all six landscape databases**." An earlier wording here said landscape 01 was "short only vp 2066", which reads as though it also escaped `tasmin` 1958. It does not: `tasmin-1958` has no CRS either, so no fallback is reachable for it. And because `vpd = es(tasmin, tasmax) − vp`, landscape 01 still loses vpd for 1958 despite holding a good `vp-1958` — the intact file cannot compensate for the missing `tasmin`.)*

**LANDSCAPE 01 IS NOT EXEMPT — flagged again 2026-11-16, because it is easy to assume it is.** CPCRW having "its own climate source" rescues it from the two **1958** defects, which fall below the 1980 run start anyway, but **not from `vp-2066`, the only one inside the 2015–2100 window**. Landscape 01's NorEsm2-MM/ssp245 replicates ran 2066 with no vpd exactly like 02–06, so it is included in both re-run sets.

**Why the fallback cannot help, and the general rule.** `03_climate_create.r` (~lines 99–109) is not a per-landscape source switch: it loads the **Landscapes** file first for every landscape, then drops to CPCRW only if the crop over the landscape extent is all-NA.
```r
ak_climate_var <- rast(clim_in)                                            # Landscapes, always first
env_ext_clim_crs <- project(ext(env_rast), ..., to = crs(ak_climate_var))  # THROWS if CRS missing
if (all(is.na(values(crop(ak_climate_var[[1]], env_ext_clim_crs))))) {
  ak_climate_var <- rast(cpcrw_clim_in)                                    # only if the crop is all-NA
}
```
`vp-1958`'s defect **is** all-NA over the domain, so the fallback fires and CPCRW's intact copy is used. `vp-2066`'s defect is a **missing CRS**, so `project()` throws on the line *before* the fallback test, `tryCatch` swallows it, and the year is never written — the intact CPCRW copy is never reached. **So: the CPCRW fallback rescues the all-NA failure mode only, never the missing-CRS one.**

**Impact:** 1958 is below the 1980 start of every run, so it costs nothing. **2066 is inside the 2015–2100 window**, so every completed NorEsm2-MM/ssp245 replicate ran a year with no vpd — and all 936 runs reported `*** model run finished.`, so iLand accepted it silently. Whether that warrants re-running is a science question for Winslow; **no gap-filling was done**, by decision. The fri 10/15/30 round had not been submitted, so nothing was burning compute on it.

**Three guards added**, each verified to fire against a fixture and to stay silent on clean data:
1. `03_climate_create.r` — the error handler now also raises a `warning()` naming landscape/gcm/ssp/var/year plus the condition message, **outside** the `log_msg` mechanism so it speaks at the default `logs = FALSE`. A silent handler on a network-dependent loop hides typo'd names and dropouts just as readily as bad files.
2. `04_climate_create.r` — before joining, assert all five variables share one year set; `stop()` listing each short variable and its missing years. Maps directly onto the observed fault.
3. `04_climate_create.r` — after assembly and before writing, `stop()` if any of `min_temp, max_temp, prec, rad, vpd` holds an NA, reporting count and years per column. This is the backstop for NA *content* in a file that exists — the `vp-1958` class, which a year-set check cannot see.

Guards 2 and 3 are deliberately separate: 2 gives a precise early diagnosis, 3 catches what nobody predicted. Verified by running the real `process_sqlite` against a fixture: disagreeing year sets stop with both offenders named; an all-NA variable stops reporting `vpd` (not `vp`, since only the columns that reach the database are checked); clean data builds exactly as before.
**Why:** the data defect was someone else's to fix, but the months of silence were ours. A `tryCatch` whose handler is `invisible(NULL)` is not error handling, and a left join onto a complete anchor turns missing inputs into plausible-looking NULLs.

---

### 2026-10-15 — Short-interval fire round: fri 10, 15 and 30
**Context:** The fri 60 / 120 round is complete and post-processed (312 lines, 936 runs, all verified). This round extends the fire-frequency contrast downward with fri **10, 15 and 30**, in exactly the same shape: 6 landscapes × 2 SSPs × 3 GCMs × (12 reps onlysim=false + 1 onlysim=true).
**Decision/Finding:** **Two files changed and nothing else** — twelve new CSVs in `scenario-launch/`, and `FRIS="60 120"` → `"10 15 30"` in `generate_cmdfiles.sh`. No XML edits, no landscape-directory changes, and no new spinups: `fri` reaches iLand as a command-line override (`modules.fire.fireReturnInterval=${fri}`, runner line 89) read from the CSV's third column, and every CSV points at the same `snapshot/spinup_300`. The new CSVs were derived from their fri60 counterparts by rewriting field 3 with `awk -F, -v OFS=, '{$3=F}'` — field-indexed rather than `sed s/,60,/,10,/`, so nothing else could be touched; verified by diffing each against its source with field 3 masked, which showed no other change.

**NEW VALUES ONLY — 60 and 120 are deliberately absent from `FRIS`, and must stay absent.** `scenario_id` is keyed on fri (`${gcm}_dbh${dbh}_onlysim${onlysim}_fri${fri}`), so 10/15/30 land in entirely new output directories and cannot touch the completed round. The converse is the hazard: putting 60 or 120 back into `FRIS` "to have them all in one place" would target the existing directories, and the runner clears each `scenario_dir` unconditionally — destroying 936 verified replicates. The five-way contrast lives on scratch across two rounds, not in one cmdfile set. The generator header now says so.

**Scale: 468 lines, 1404 model runs — 1.5× the previous round.** Each chain is 156 lines, batching as **32/32/32/32/28**; 28 is 7 nodes at `--steps-per-node 4`, still a multiple of 4, so no node runs under-filled. Verified after regeneration: only `fri10/15/30.csv` referenced (156 lines each), all 12 referenced CSVs exist on disk, 468 lines across 15 cmdfiles, zero blank lines, chains mapping to the right landscape pairs, and reps 1–12 for `onlysim=false` against rep 1 only for `true`.

**Concurrency: one chain at a time, and the reason is worth restating.** A single chain now runs **32 concurrent models** — 32 lines × 8 nodes × 4 steps/node. That is the figure measured on 2026-09-09 with no slowdown and no I/O trouble, but it used to be the *combined* total across two 4-node chains; the 2026-09-13 batch collapse (`NODES_PER_JOB` 4 → 8) moved it inside one chain. So submitting A and B together would now be 64 concurrent models, double anything tested. Submit A, let it finish, then B, then C.

**Walltime is the open risk.** Chain C ran at **95% of the 12 h cap** (11.36 h worst subjob, 38 minutes of margin), and fri 10 is roughly a fire a decade rather than one or two a century. The runtime effect is **unknown**: more fire kills more trees, which usually makes iLand faster, but that is inference, not measurement — and in the chain C timers seed dispersal dominated at 2 h 31 m of a 2 h 38 m `runYear`, so an opened-up landscape could cut either way. Read `qhist` on chain A batch 1 before letting the remaining four batches run. If a subjob drifts past ~11.5 h the lever is splitting CSVs to one GCM per line (~3.6 h/line, 3× the lines, identical node-hours, better backfill) — not a longer walltime, since 12 h is effectively Derecho's cap.

**Downstream consequence to remember:** `analysis-scripts/generate_process_cmdfiles.sh` globs **all** `iland_scenarios_ssp*_sim*_fri*.csv`, so now that these 12 exist it will emit area_dom lines for **60 treatments instead of 24** — including fri60/120, which are already processed. Re-processing is safe (it recomputes into `processed/`) but wasteful; that round wants a fri filter or a scoped run.
**Why:** the whole round is a one-line matrix change precisely because fri was pushed out to per-CSV command-line overrides rather than baked into the XMLs — and the one thing that could go badly wrong is re-running a completed fri, which the generator header now warns about at the point of edit.

---

### 2026-09-16 — Per-replicate fire tables and KBDI gathered alongside area_dom
**Context:** area_dom processing writes one directory per replicate, but the `fire` table and the annual KBDI grids were still only on scratch in the raw run tree. Both are needed per replicate, on the receiving drive, in the same place as area_dom.
**Decision/Finding:** Two scripts, `analysis-scripts/gather_fire_kbdi.R` (Derecho login node) and `analysis-scripts/unpack_kbdi.R` (receiving drive). Gather writes `processed/<treatment>/rep_<N>/fire/fire_table.csv` and `processed/<treatment>/rep_<N>/kbdi/kbdi.tar.gz` — beside `area_dom/`. The fire CSV carries landscape/treatment/replicate columns so the files row-bind later without losing provenance.

**KBDI is archived rather than copied.** A scenario replicate writes one grid per simulated year, so the full set across landscapes 01–05 is ~86 × 780 ≈ **67,000 small files**. That many Lustre metadata operations from a login node is slow and antisocial; one archive per replicate is 780 operations, and far quicker to transfer off Derecho. The archives hold **relative** paths (`./kbdi_1.txt`, not `/glade/...`), which is what lets `unpack_kbdi.R` untar them in place on any machine — it uses R's own `untar()`, so Windows works. Both scripts are idempotent: gather skips a replicate whose CSV and archive both exist, unpack skips a directory that already has loose grids, so an interrupted transfer just gets re-run. Tarballs are left in place after unpacking; delete them deliberately with `find <root> -name kbdi.tar.gz -delete`.

**The completeness test is the KBDI grid count, and it is derived rather than hard-coded — because the expected count differs by workflow.** Scenario is **86**, confirmed by the user from the Derecho output, with no empty year-0 grid: `saveWorkflow_scenario.js` calls `saveKBDI()` from `onYearEnd` with no guard, one grid per simulated year. Spinup is **~31**, because `saveWorkflow_spinup.js` wraps the same call in `if (Globals.year % 10 == 0)` over 300 years. Hard-coding 86 would therefore break the moment the script were pointed at spinup output. Instead it counts the grids in every replicate, takes the **mode**, processes the replicates matching it, and lists any that differ. Verified against a synthetic tree of 8 replicates — it derived 86 unaided and flagged the one seeded with 40 grids.

**RUN 2026-09-17 — all six landscapes in one login-node pass: 936 replicates, 86 grids each, 0 with a wrong count, 0 failed.** That is ~80,500 grids read and gzipped, and it completed without troubling the login node. **The result doubles as an independent completeness check on the whole scenario round:** a replicate only writes its 86th grid if it reached the final simulated year, so 936/936 at exactly 86 (936 = 6 × 156) corroborates the `.complete` sentinel audits by an entirely different route.

**KNOWN FLAW in the resume guard, not yet fixed.** The check is `file.exists(fire_csv) && file.exists(kbdi_tar)`, and the CSV is written *before* the tar. A run killed mid-`tar` therefore leaves a complete CSV beside a **truncated archive**, and a re-run would see both files, skip the replicate, and carry the corrupt archive through to transfer unnoticed. The fix is to tar to a temporary name and rename on success, so a partial archive never holds the final name. Until then, verify before transferring:
```
find <root> -name kbdi.tar.gz | while read f; do gzip -t "$f" 2>/dev/null || echo "CORRUPT: $f"; done
```

**The archives stay packed on Derecho by design** — `unpack_kbdi.R` expands them on the receiving drive. Unpacking them in place would recreate the ~80,500 loose files the tarring exists to avoid, though running the unpacker against the scratch root is a valid choice if the grids are wanted there too.

**Worth knowing for diagnosis:** iLand's `Saved KBDI for year N` message goes to its own `log.txt` in the replicate directory, **not** to job stdout, so downloaded `step-*.out` files cannot be used to confirm KBDI behaviour.
**Why:** the archive-not-copy decision is the difference between a login-node loop that finishes and one that hammers the filesystem for hours; and the derived count is what stops the same script silently discarding every spinup replicate later.

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
