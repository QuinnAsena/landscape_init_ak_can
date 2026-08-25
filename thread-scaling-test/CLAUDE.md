# CLAUDE.md — thread-scaling-test

Orientation for an agent picking this up cold. **The study is finished.** Read `report.md` before
running anything; almost every question that looks open has already been measured, and re-running
costs hours.

## What was settled (do not re-derive)

| question | answer |
|---|---|
| Does iLand scale with threads? | No, past **8**. 8 → 32 threads changes total runtime ~1%. |
| Is that just output cost? | No. With all writers off, compute is 109 s at 4 threads, 93 at 8, then 111/110/105 at 16/24/32. |
| Why? | `outputs` is serial (one SQLite connection). **Seed dispersal is parallel over *species*, not resource units** — 4 species here, measured at 3.24× effective parallelism in production. The thread-scalable phases are ~15% of a run. |
| Does thread count affect memory? | **No.** 29.71 GB at 8 threads vs 29.66 at 32, reproducible to 0.1%. |
| What does affect memory? | Simulated years, and it is **model state, not output buffers** — 86 yr with writers off is 35.76 GB vs 37.37 GB with them on. |
| Is oversubscription costly? | Not for one instance (421 s at 256 threads vs 433 at 8). **Yes for concurrent instances**: 3 × 16 threads beat 3 × 256 by 6.0%. |
| Are GeoTIFF grid inputs equivalent? | Yes, `stand` rows agree to 0.002%. No reliable speed gain — creation is dominated by `loadSnapshot` (~85 s, identical across formats). |
| Can a write queue fall behind? | No. Writes are synchronous inside the year loop. |

## Traps that have already bitten

**Tag collisions destroy results silently.** A tag (`t8`, `n16`, `m8`) names the log, the memory
files and the sandbox output dir, and `run_one` does `rm -rf` on that dir first. An 86-year
writers-off run once took the tag `n8` and overwrote the 5-year `n8` from the thread sweep,
invalidating a published table. **Always set `TAG_SFX` when re-running a mode with different
parameters.** `parse_timers.R` now folds the suffix into the family name and refuses to compare
runs of differing `years`, printing `SKIPPED, mixes 5/86 simulated years` instead.

**Read the right thread-count log line.** `Multithreading enabled: true thread count: N` is the
**machine's** logical processor count and is identical whatever you request.
`Multithreading: set max thread count to N` is the applied value and appears **only** when
`threadCount` is set explicitly. Its *absence* is how we established production was running at
`-1`. Grep for the second, never the first.

**Never edit `run_thread_scaling.sh` while it is running.** Bash reads scripts incrementally; the
running instance can jump to a wrong byte offset.

**Shell heredocs in this environment halve backslashes**, and Python then reads `\` + newline as a
line continuation. Several edits here failed silently that way, including one that caused the tag
collision above. Build backslashes with `chr(92)`, or use the `Write` tool for anything
non-trivial.

**Timing noise is ~10–15%** on identical configs (`m32` vs `t32`: 218 vs 248 s). Nothing below
that is a result. Memory, by contrast, reproduces to 0.1% — trust it far more than any timing.

## Layout

- `report.md` — the findings. The deliverable; keep it in step with any new numbers.
- `setup_sandbox.sh` — provisions `D:/quinn/iland_sandbox/landscape_test` from
  `landscape_alaska_01`. **The sandbox was deleted on 2026-08-25** after the study finished; this
  rebuilds it (~14 GB, mostly climate DB + snapshot). Its snapshot is deliberately named
  `spinup_300_TIMING_ONLY.sqlite` — a timing artefact, *not* the snapshot landscape_alaska_01
  should use scientifically.
- `run_thread_scaling.sh` — modes `threads | nooutput | geotiff | memthreads | concurrency`.
  Env: `YEARS`, `THREADS`, `MEM_THREADS`, `TAG_SFX`, `CONC_N`, `CONC_THREADS`, `SEED`.
- `poll_memory.ps1` — samples summed `ilandc` working set (peak, plus optional `-TraceFile`).
  Polling is necessary: `PeakWorkingSet64` does not survive process exit.
- `parse_timers.R` → `results/thread_scaling.csv`; `plot_scaling.R`, `plot_memory.R`,
  `plot_peryear.R` → `results/*.png`.
- `results/thread_scaling_ARCHIVED.csv` — holds `stand_rows`/`fire_rows`, which **cannot be
  recomputed** now the sandbox databases are gone. Do not let a re-parse overwrite it.
- `results/derecho_log_excerpt.txt` — the load-bearing lines from the 103 MB production log.

## Repo hygiene

iLand logs are ~97 MB **each**. `results/log_*.txt` and `derecho_temp_log.txt` were committed
before `.gitignore` covered them, which is most of why `.git` is ~8 GB. They are ignored now, so
do not re-add them; if the working tree needs cleaning, `git rm --cached` them rather than
deleting, and do not rewrite history without asking — the commit is already pushed and Derecho
has a clone.
