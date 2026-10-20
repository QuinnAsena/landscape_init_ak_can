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

### 2026-10-20 — NorEsm2-MM excluded from ssp245 only; priority raised to premium
**Context:** Ten days left in the project timeline, the fri 10/15/30 round still unsubmitted, and the NorEsm2-MM/ssp245 climate known corrupt (2026-10-16 entry).
**Decision/Finding:** **NorEsm2-MM is excluded from ssp245 alone**, by deleting its row from the six `iland_scenarios_ssp245_sim{false,true}_fri{10,15,30}.csv` files. TaiESM1 and UKESM1-0-LL under ssp245 are clean and are kept; all of ssp370 keeps all three GCMs. Priority went `economy` → `premium` in `submit_chain.sh`.

**A first attempt dropped ssp245 wholesale and was wrong** — it discarded two good GCMs and the entire SSP contrast to remove one bad one. The reason the blunt version looked necessary is worth recording: a cmdfile line loops **every row of its CSV**, so the GCM set is a property of the CSV, not of the line. Excluding one GCM from one SSP therefore means editing those CSVs, not the generator. Once that was seen, the targeted fix was six `grep -v` edits.

**Scale: 468 lines, 1170 model runs** — and the run count is no longer 3× the line count. ssp370 lines loop three CSV rows, ssp245 lines two: 234 × 3 + 234 × 2 = 1170. The generator used to print `total * 3`, which would now be wrong by 234 runs, so it **counts each CSV's GCM rows instead of assuming three**. The same stale-multiplier assumption is what the climate guards were added to prevent a fortnight ago.

**Two side effects of keeping ssp245, both good.** The chain is back to 156 lines → **5 batches of 32/32/32/32/28**, which divides cleanly by `STEPS_PER_NODE=4`, so the under-fill warning the ssp370-only variant produced is gone (78 is not a multiple of 4; 156 is). And an ssp245 line is now about two thirds the work — roughly 5–7 h against 8–11 h — so **half the round has a wider margin against the 12 h walltime** than the fri 60/120 round did. That matters because chain C previously peaked at 95% of walltime.

**Premium is deliberately temporary.** It charges 1.5× against the allocation, bought to cut queue wait with the deadline close, and the allocation has the hours. It is the right lever rather than more packing: the 2026-09-16 timing study showed these chains are **queue-wait dominated** (gaps of 7, 76 and 78 minutes between batches against ~35 minutes of compute). **Drop back to economy once the deadline passes.** Only `scenario-launch/submit_chain.sh` changed — `submit_chain_spinup.sh` and `analysis-scripts/submit_chain_process.sh` are still economy, so this round's area_dom processing will queue at the old priority unless raised.

Verified after regeneration: all 12 fri10/15/30 CSVs referenced and no fri60/120 leakage; **NorEsm2-MM present in 6 of 6 ssp370 CSVs and 0 of 6 ssp245 CSVs**; the fri 60/120 CSVs untouched and still carrying three GCMs; 15 cmdfiles, 468 lines, zero blanks, 432 simfalse / 36 simtrue.
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

**Scope, audited:** all 54 combinations (6 landscapes × 3 GCMs × 3 SSPs) were checked for variables disagreeing on their year set. **Only NorEsm2-MM/ssp245 is affected.** Landscapes 02–06 are short `tasmin` 1958 and `vp` 1958+2066; landscape 01 is short only `vp` 2066, via the CPCRW fallback.

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
