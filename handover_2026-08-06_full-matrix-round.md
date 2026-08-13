# Handover — 2026-08-06 — Derecho full-matrix scenario round

Working notes from the session that built the new Derecho batch submission. Written
to the repo so it survives a machine restart and syncs to the other two machines.
**Nothing has been committed or submitted** — all changes are uncommitted working-tree
edits awaiting review.

---

## 1. What this round is

Completes the full grid of **6 landscapes × 3 SSPs × 3 GCMs × onlysim true/false**.
Landscapes 01–03 at ssp245 were finished in the July rounds, so this round covers
everything else:

| Landscapes | SSPs | onlysim | Reps |
|---|---|---|---|
| 01–03 | 126, 370 | false | 1–12 |
| 01–03 | 126, 370 | true | 1–3 |
| 04–06 | 126, 245, 370 | false | 1–12 |
| 04–06 | 126, 245, 370 | true | 1–3 |

**225 cmdfile lines → 675 model runs.** One line = one landscape × one ssp × one
onlysim × one rep, looping the three GCM rows in its CSV, so roughly 8 hours of work
per line inside a 12-hour walltime.

GCMs are `NorEsm2-MM`, `TaiESM1`, `UKESM1-0-LL`. The SSP is embedded in the `gcm`
string (`NorEsm2-MMssp126`), which is also the climate database name — all nine
GCM×SSP databases were confirmed present in every landscape's `databases/` folder.

### Two things that are easy to get wrong

**These are scenario runs, not spinups.** Every line uses
`landscape_alaska_0N/landscape_alaska_0N_2015-2100scenario.xml` with 86 simulation
years. Not `_1950-1980spinup.xml`, and not `_2015-2100scenario_onlyfire.xml` (the
onlyfire variant is the separate Cuddles-local track — it differs only in having four
output blocks disabled). The spinup is an *input*: each line picks up
`snapshot/spinup_300.sqlite` through the CSV's `snapshot_file` column.

**`onlysim` reads backwards from what you'd expect.** `onlysim=false` means fire
genuinely burns biomass and affects the landscape. `onlysim=true` means fire is
simulated but has no effect. Replication therefore doesn't matter for onlysim=true;
its 3 reps exist only to fill a node at `--steps-per-node 3`, while onlysim=false
keeps its full 12.

That 3 also makes the batch arithmetic work out. Each landscape-ssp block is 12 + 3 =
15 lines, and 3 divides both 15 and the 12-line batch, so every trailing batch is a
multiple of 3 and no node is left running fewer reps than it could. `generate_cmdfiles.sh`
re-checks this and warns if a future matrix change breaks it.

---

## 2. Why steps-per-node stays at 3

Four simulations per node was proposed and then ruled out on evidence. From the
Derecho usage report (three 1-node array elements, 3 steps each, nthreads=40):

```
Job ID       User       Queue    Nodes  NCPUs NGPUs     End      Mem    CPU   Elap
6836992[0]   qasena     cpu          1    128     0 23-0127   118.15  94.71   7.91
6836992[2]   qasena     cpu          1    128     0 23-0129   156.94  93.56   7.91
6836992[1]   qasena     cpu          1    128     0 23-0130   118.84  95.71   7.93
```

`CPU` ≈ 95% means ~121 of 128 cores are already busy — the node is compute-bound. A
fourth step doesn't create capacity, it divides the same saturated CPU four ways:

| | 3 × 40 threads | 4 × 32 threads |
|---|---|---|
| Time per line | 7.91 h (measured) | ~10.5 h (7.91 × 4/3) |
| Lines per node-hour | 0.379 | 0.379 |
| Peak memory | 118–157 GB (50–67%) | ~209 GB (89%) |
| Walltime margin | 4.1 h | ~1.5 h |

Identical throughput, but memory rises to 89% of the 235 GB request and the walltime
cushion drops to 90 minutes. **Concurrency comes from node count instead.** This would
only differ if the runs were I/O-stalled, leaving spare cores for a fourth step —
at 95% CPU they aren't.

---

## 3. Changes made

### `run_iland_csv_cpxml_apptainer.sh` — three edits

Only the Derecho runner was touched. `run_iland_csv_cpxml.sh` (local/Cuddles) was
deliberately left alone; the two have diverged on purpose and are not interchangeable.

**a. Optional 5th positional CSV argument**

```bash
csv_name="${5:-${script_dir}/iland_scenarios.csv}"
```

`${5:-default}` uses `$5` if set and non-empty, otherwise the default — so any
existing four-argument cmdfile line behaves exactly as before. The `:-` form is
exempt from `set -u`. Verified both paths under `set -euo pipefail`.

This replaces the alternative of rewriting a single `iland_scenarios.csv` between
submissions, which is a silent-corruption hazard: with `afterok` chaining the CSV is
read when a job *starts*, not when it is submitted, so a queued job would pick up
whatever the file was edited to say hours or days later.

**b. `.complete` sentinel resume guard**

```bash
if [ -f "${scenario_dir}/.complete" ]; then
    echo "Skipping gcm $gcm, id $id, rep $rep (already complete)"
    continue
fi
```

with `touch "${scenario_dir}/.complete"` after the `apptainer exec` block. Because
`set -e` is active, the touch is only reached if `ilandc` exited 0. Testing for the
output `.sqlite` instead (as the local runner does) would also skip walltime-killed
reps that got as far as creating a partial database.

**c. Clear a partial rep before resuming**

```bash
rm -rf "${scenario_dir}"
```

immediately before the `mkdir -p` calls. This matters more than it looks:
`saveWorkflow.js` names fire grids `kbdi_<Fire.id>_<year>.txt`, keyed to the fire
event counter and burn year, and reps are not seeded — so a resumed replicate burns
differently. Without the clear, `kbdi_1_29.txt` from the killed run and
`kbdi_1_34.txt` from the resumed run would sit in the same `rep_N/` folder and the
fire analysis would silently read two realizations as one.

### New files

- **Six scenario CSVs** — `iland_scenarios_ssp{126,245,370}_sim{true,false}.csv`,
  three GCM rows each, `id=yr_1_iLand2.1` throughout (needed for downstream string
  matching). Generated from a loop so the rows cannot drift apart.
- **`generate_cmdfiles.sh`** — emits `cmdfile_ch{A,B,C}_NN.sh` deterministically from
  the matrix. **Edit the matrix here, not the cmdfiles** — regenerating overwrites
  them wholesale.
- **20 cmdfiles** — chain A 5 batches, B 7, C 8; 12 lines each, with trailing batches
  of 3 (chain B) and 6 (chain C), both multiples of `--steps-per-node`.

### `submit_chain.sh` — rewritten

Now takes a chain letter: `bash submit_chain.sh A`. Three independent chains split by
landscape so they never touch the same source directory:

| Chain | Landscapes | Lines | Batches |
|---|---|---|---|
| A | 01, 02 | 64 | 6 |
| B | 03, 04 | 80 | 7 |
| C | 05, 06 | 96 | 8 |

Each batch is 12 lines = 4 nodes at `--steps-per-node 3 --nthreads 40`, so 12
concurrent reps per chain. Launch A first; once it runs clean add B, then C. That
takes concurrency 12 → 24 → 36 in deliberate steps rather than one jump. Still uses
`| tail -1` to extract the job ID, since `launch_cf` prints diagnostics first.

### Deliberately not done

The temp-XML orphan fix (process substitution + widened trap) was dropped. Removing
the pipe also removes the `pipefail` protection that currently catches a bad CSV path
loudly, so it would have needed a companion `[ -s "$csv_name" ]` check — two edits for
a cosmetic benefit. Sweeping is now a documented one-liner in `submit_chain.sh`'s
header instead, and is kept *out* of the script body because a sweep firing while
chain A is mid-flight would delete chain A's live temp XMLs:

```bash
rm -f landscape_alaska_0*/*_dbh2.5_onlysim*.xml   # only when no job is active
```

---

## 4. Verification performed

- All 225 lines expanded against their CSVs → **675 output keys, all unique, zero
  collisions.** Key is landscape × gcm-with-ssp × dbh × onlysim × id × rep.
- Every generated batch is a multiple of `--steps-per-node` (12, plus trailing 3 and
  6), so no node runs under-filled.
- Per-landscape/ssp/onlysim breakdown matches the spec exactly.
- `bash -n` passes on all three scripts.
- CSV argument default verified under `set -euo pipefail` for both 4-arg and 5-arg
  calls.
- The `sed "s|<output>.*</output>|...|"` substitution matches **exactly one line** —
  line 12, inside `<system><path>`. The big `<output>` section opener at line ~496
  does not match because the pattern needs both tags on one line, and the comment at
  line 26 has no closing tag on its line.
- iLand writes the output `.sqlite` into `scenario_dir`, confirmed by `find` against
  real output — so the resume guard looks in the right place.
- `saveWorkflow.js` is current on all six landscapes (redeployed 4 Aug 13:38, after
  the master's 12:57 edit, KBDI call present). Derecho confirmed to have the latest.

---

## 5. Still to do

1. **Review the diff** (the reason this file exists).
2. **Smoke-test landscapes 04–06** — one rep each before committing 432 runs to them.
   They have complete inputs and spinup snapshots on Derecho, but their scenario XMLs
   have never actually executed; only spinups have run there.
3. **Sync to Derecho**, then `bash submit_chain.sh A`. The six
   `_2015-2100scenario.xml` files were regenerated on 2026-08-13 to fix the climate
   resampling bug (see NOTES.md) — the Derecho copies are stale until re-synced, and
   submitting before that would run the whole round on randomised climate years.
4. **Housekeeping:** `cmdfile_b01.sh`–`b06.sh` and `cmdfile_runreplicates_csv_iland2.1.sh`
   are now referenced by nothing. Left in place rather than deleted.
5. Landscapes 05 and 06 were missing `snapshot/spinup_300.sqlite` on Cuddles; that
   download was started. Derecho already has the correct files.

## 6. Budget notes

- Disk: a full-output replicate is ~440 MB (mostly `area_dom`) plus a ~103 MB
  `log.txt`, so the round is roughly 0.6–1 TB on scratch. Against a 30 TB quota this
  is not a constraint.
- Chain depth: ~1 day per link including queue wait, so 6–8 links per chain is roughly
  a week per chain with all three running in parallel.

---

## Appendix — session summary as delivered

Preserved verbatim, so its counts are the pre-revision ones: it says 240 lines / 720
runs / 21 cmdfiles, from when onlysim=true still had 4 reps. Current figures are 225
lines, 675 runs, 20 cmdfiles — see section 1.

> Built and verified. Everything is scenario runs against
> `landscape_alaska_0N_2015-2100scenario.xml` for all six landscapes — the spinup
> snapshots are consumed as initialization input, never re-run.
>
> **Three changes to the runner, all load-bearing.** I dropped the two you were right
> to question: the process-substitution orphan fix would have forced a companion
> CSV-existence check (removing the pipe removes the `pipefail` protection that
> currently catches a bad CSV path loudly), which is two edits for a cosmetic gain.
> Orphan sweeping is now just a documented one-liner in `submit_chain.sh`'s header,
> run manually when nothing is active — I deliberately kept it out of the script body,
> because a sweep that fires while chain A is mid-flight would delete chain A's live
> temp XMLs.
>
> What did go in: the optional fifth CSV argument, the `.complete` sentinel guard, and
> `rm -rf "${scenario_dir}"` before a resumed rep. I checked that the argument default
> behaves under `set -u` — a four-argument call from any old cmdfile still resolves to
> `iland_scenarios.csv` unchanged.
>
> **Files.** Six static CSVs (`iland_scenarios_ssp{126,245,370}_sim{true,false}.csv`),
> `generate_cmdfiles.sh` which emits the 21 cmdfiles deterministically, and
> `submit_chain.sh` rewritten to take a chain letter: `bash submit_chain.sh A`.
>
> The generator produced 240 lines — chain A 64, B 80, C 96 — and expanding every line
> against its CSV gives **720 output keys, all unique, zero collisions**. The
> per-landscape breakdown matches your spec exactly: landscapes 01–03 carry only ssp126
> and ssp370, landscapes 04–06 carry all three, with 12 reps at `onlysim=false` and 4 at
> `onlysim=true` throughout. All three scripts pass `bash -n`.
>
> **Edit the matrix in the generator, not the cmdfiles.** Regenerating overwrites
> `cmdfile_ch[ABC]_*.sh` wholesale, so any hand-edit there is lost on the next run.
>
> Two things left for you. The old `cmdfile_b01.sh`–`b06.sh` and
> `cmdfile_runreplicates_csv_iland2.1.sh` are now unreferenced by anything — I left them
> rather than delete files you might still want. And before committing 432 runs to
> landscapes 04–06, run one rep on each: they have complete inputs and spinup snapshots,
> but their scenario XMLs have never actually executed, so a smoke test buys real
> information cheaply.
>
> When you're ready: sync to Derecho, then `bash submit_chain.sh A`. Once A is running
> clean, add B, then C — that takes you 12 → 24 → 36 concurrent, which is the controlled
> version of upscaling until error.
