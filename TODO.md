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
- [x] Chain C batches 1–2 verified by sentinel: 96 expected / 96 complete / 0 partial /
      0 missing each. **Landscapes 01–05 confirmed ready for post-processing**
- [x] area_dom cmdfiles generated as **batches** for landscapes 01–05. `NODES_PER_JOB=3` in
      `generate_process_cmdfiles.sh` gives 36 lines / 3 nodes per batch, so 4×36 + 12 per
      landscape = **25 batches, 780 lines** (verified lossless against the unbatched files)
- [x] `analysis-scripts/submit_chain_process.sh` — plain glob-and-chain, 41 executable lines
      against `submit_chain.sh`'s 36. Batching lives in the generator, not the submitter.
      Takes `<analysis> <kind>`, so scenario and spinup are always separate chains
- [ ] **Submit the chain, then measure the first batch:**
      `bash analysis-scripts/submit_chain_process.sh area_dom scenario`
      Only one batch runs at a time, so batch 1 is measurable on its own — read
      `qhist -j <first jobid>` for mem/node and elapsed, and `qdel` the held successors if it
      looks wrong. Per-step memory is UNMEASURED for scenario processing (10–20 GB/step
      plausible; at 12 steps/node that is 144–240 GB of 235). If it lands near 20 GB/step,
      drop `--steps-per-node` in **both** the generator and the submitter
- [ ] area_dom for landscape 06 once 7431376 finishes — generate its batches and chain them;
      the per-landscape naming makes it additive, nothing else is regenerated
- [ ] A completeness checker for *processing* output — `check_cmdfile_complete.sh` parses the
      iLand runner signature and does not work on processing cmdfiles
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
