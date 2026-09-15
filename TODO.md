# TODO

## In flight — 2026-09-13

- [x] Chains A + B verified complete (624/624 runs, zero errors in `std_out/`)
- [x] Batch size collapsed 4 → 8 nodes (`NODES_PER_JOB` in `scenario-launch/generate_cmdfiles.sh`)
- [x] **Chain C submitted: 7431373–7431376**, 4 batches, landscapes 05/06
- [x] Chain C batches 1–2 done; `afterok` released cleanly twice. **Landscape 05 complete,
      landscape 06 has 40 of 52 lines outstanding** (7431375 running, 7431376 held)
- [x] `-r n` — **CLOSED, do not do it.** NCAR: `-r y` is hard-coded in `launch_cf` and adding
      `-r n` "may be ill defined"; leave it as is. Mitigation is procedural — have NCAR DELETE
      a job, never requeue it
- [ ] **area_dom post-processing for landscapes 01–05** (hold 06 until chain C finishes).
      `generate_process_cmdfiles.sh --kind scenario --analysis area_dom --landscapes "01 02 03 04 05"`
- [ ] Build the area_dom submission **chain** — beware: spinup processing cmdfiles are 1 node
      (NOT arrays), scenario ones are 13 nodes. Keep them in separate chains, or detect
      array-ness before setting the dependency
- [ ] Adopt `afterokarray` once the processing chain proves it. The helper and reasoning are
      parked in `NOTES.md` (2026-09-13 entry), **not** in the scripts — paste it in and swap
      the one line. **Separate branch of work from the area_dom cmdfiles**
- [ ] Chain C walltime is at **95% of 12 h** (11.36 h on 7431374[1], vs 90% for chain A and
      83% for B). Fine for the remaining 2-node batch, but treat 12 h as marginal for any
      future round at these settings

See `NOTES.md` (2026-09-13 entry) for the full reasoning.

## Current Phase: Local Testing + HPC Deployment

### Local Testing
- [ ] Single-site validation: run `cpcrw_test.r` (Caribou-Poker Creeks) end-to-end
- [ ] include post-run processing scripts in bash?

### HPC Deployment (NCAR Derecho)
- [ ] Upload pipeline outputs to Derecho
- [ ] Verify bash job scripts (`run_iland_csv_cpxml.sh`) work on Linux
- [ ] Test iLand model run on HPC with a single landscape
- [ ] Scale to full set of landscapes

---

## Backlog

- Address Priority 1 correctness issues from `issues-codex5.3.md` when relevant. Most of the defensive checks are unnecessary at the moment.
- clean up scripts 01 and 10. They will source but are not tidy functions like the other scripts!
- Create master sourcing script to run the workflow from a central script. Low importance since this only needs to be done once if everything works!
