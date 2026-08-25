# Thread-scaling benchmark

Measures how iLand runtime responds to thread count, to decide the
`--steps-per-node` × `--nthreads` split for the Derecho scenario round.

```bash
bash thread-scaling-test/setup_sandbox.sh        # ~14 GB into D:, once
bash thread-scaling-test/run_thread_scaling.sh   # the sweep, ~1 h
Rscript thread-scaling-test/parse_timers.R       # results table
```

Run nothing else on the machine while the sweep is going.

## The project file has to be patched, and setup does it

The scenario XML ships twelve placeholders. Three (`system.path.output`,
`system.database.out`, `system.logging.logFile`) are set per run by the harness.
The other **nine come from a CSV row** in production, where the runner passes them
on the command line and appends the file extensions the CSV omits.

`setup_sandbox.sh` bakes those nine into the sandbox XML by calling
`patch_sandbox_xml.R` against `spin-up-launch/iland_spinups.csv`, so the benchmark
project file is self-contained *and* still derived rather than hand-edited. Set
`PARAM_CSV` to use a different row; point it at a scenario CSV only if you also
copy that GCM's climate database.

Skipping that step fails in two different ways, one loud and one not:

```
Environment: input file does not exist (.../overwritten_by_csv)   # loud
epsilon=0                                                        # silent
```

The second is the dangerous one — the run completes and the timings describe the
wrong workload. `run_thread_scaling.sh` therefore refuses to start if
`environmentFile`, `epsilon` or `fireReturnInterval` still hold a placeholder.

## What it measures, and why not just wall time

If output writing is single-threaded — very likely, since SQLite writes through one
connection, and the old Derecho spinup spent 4 h 17 m of a 7 h 18 m run in `outputs` —
then total time is `serial_output + parallel_compute` and only the second term
responds to threads. iLand's own timer block separates them, so the parser reads
the split directly rather than fitting Amdahl to a black box.

Two questions come out:

1. **Is output serial?** `outputs` against thread count. Flat means it is a fixed
   cost per output-year that no packing decision reduces — only writing fewer
   years or fewer tables would.
2. **How does compute scale?** `runYear − outputs` against thread count, and where
   it saturates.

## Design decisions worth knowing

**Threads stay ≤ 32.** This machine is a Threadripper 7970X: 32 physical cores, 64
logical. Derecho's 40 threads are 40 *physical* Milan cores, so anything above 32
here measures SMT behaviour that does not exist on a Derecho node and cannot be
read across.

**The seed is pinned.** The XML ships `randomSeed=0`, which is non-reproducible:
every run would burn differently, giving different tree mortality and therefore a
different amount of compute. The comparison would be between different workloads.
`parse_timers.R` gates on this — if `fire` row counts differ between configs, no
timing below it is comparable.

**Sandbox on D:, not Z:.** Z: is a network drive. The benchmark writes ~0.8 GB per
simulated year, and doing that across the network would make the `outputs` timer
network-bound — fatal, since output cost is the main quantity. Inputs are still
read from Z:, but that is constant across configs and so cannot bias anything.

**The vehicle is the real scenario configuration, not a proxy.**
`landscape_alaska_01_2015-2100scenario.xml` is already `mode=snapshot` with
`stand`/`saplingdetail`/`carbon`/`water` enabled and blank conditions, so it writes
every year. The numbers transfer to the 288-line round directly.

**Databases are kept, not deleted.** The correctness gate can only run after the
runs, and it has to pass before any timing is worth reading. ~8 GB per config on a
1.6 TB disk. `parse_timers.R` reports the total so you know what to clean.

## The snapshot in the sandbox is not a scientific input

`snapshot/spinup_300_TIMING_ONLY.sqlite` is one arbitrary local replicate at
KBDIref 0.029. It carries a realistic 68 M-tree load, which is all the benchmark
needs — but it is **not** the snapshot landscape_01 should use. That one is
selected by `analysis-scripts/process_fire_regime.R` (`best_rep`) from the Derecho
spinup outputs and downloaded manually.

The name is deliberate. A plausible-looking `spinup_300.sqlite` lying around is
exactly the trap the 2026-08-21 snapshot archive was created to close.

## Part 3: GeoTIFF inputs

```bash
bash thread-scaling-test/run_thread_scaling.sh geotiff
```

Two runs at one thread count, identical seed, swapping only the three grid inputs
between `.txt` and `.tif` (`environmentGrid`, `DEM`, `standGrid.fileName`).

**Correctness gates the speed question.** The two runs must agree on `fire` rows,
`stand` rows, and the RU count before any timing is read. A difference means the
`.tif` inputs are not equivalent — nodata handling, a type mismatch, a half-cell
offset — and timing is irrelevant.

Expect little from the speed side: 80 MB of ASCII versus 20 MB of GeoTIFF, read
once at model creation, is seconds against a multi-hour run. The value is knowing
whether it works at all, and 4× smaller inputs to sync. Any gain shows up in the
`creating model` → `running model` interval (`create_s`), not in `runYear`.

## Gotcha in the log format

iLand prints each timer name **twice** in different forms:

```
per year:  19:24:17:484: Timer "ModelController:runYear" : "1463.32ms"
summary :  20:56:19:017:       "ModelController:runYear" : "1h 32m 2s"
```

Only the summary block holds run totals. Matching the first occurrence picks up a
single year — `parse_timers.R` drops the per-year lines by their `Timer "` prefix.
Validated against the 2026-08-20 spinup log: `runYear` 5522 s, `outputs` 1531.3 s,
`seed dispersal` 3062.3 s, `OutputManager::execute()` 987.7 s, creation 339 s.

## Tags, and the one way to lose a result

Every run is identified by a **tag** (`t8`, `n16`, `m8`, `fmt_tif`, `c3x16_i1`). The tag names the
log, the peak-memory file, the memory trace and the sandbox output directory, and `run_one` does
`rm -rf` on that directory before starting. **Two runs sharing a tag means the second destroys the
first**, and nothing warns you.

This has happened once: an 86-year writers-off run was launched as `nooutput` with `YEARS=86`,
took the tag `n8`, and overwrote the 5-year `n8` from the thread sweep — silently invalidating a
published table.

So when re-running a mode with different parameters, **always set `TAG_SFX`**:

```bash
YEARS=86 THREADS=8 TAG_SFX=_y86 bash run_thread_scaling.sh nooutput   # -> n8_y86
MEM_THREADS="8 64 256" TAG_SFX=_os bash run_thread_scaling.sh memthreads
```

`parse_timers.R` folds the suffix into the family name, so `n8` and `n8_y86` are analysed
separately and can never be compared against each other by accident. It also refuses to compute
speedups for any family containing more than one simulated-year value, and prints the offending
tags instead — if you see `SKIPPED, mixes 5/86 simulated years`, you have a tag collision.

The `years` column in the timers table is there for the same reason: check it before believing a
comparison.
