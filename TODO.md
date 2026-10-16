# TODO

## In flight — 2026-10-15: short-interval fire round (fri 10, 15, 30)

- [x] 12 new CSVs in `scenario-launch/` (`ssp{245,370}_sim{false,true}_fri{10,15,30}`),
      derived from the fri60 files by rewriting field 3 only; each verified identical to
      its source in every other field
- [x] `FRIS="60 120"` → `"10 15 30"` in `generate_cmdfiles.sh` — the only functional change
- [x] Regenerated: **156 lines per chain → 5 batches [32 32 32 32 28], 468 lines,
      1404 model runs.** Verified: only fri10/15/30 referenced, all 12 CSVs exist, 0 blank
      lines, reps 1–12 for onlysim=false and rep 1 for true
- [ ] **Commit + push, pull on Derecho, then submit chain A ONLY:**
      `bash scenario-launch/submit_chain.sh A 2>&1 | tee scenario-launch/submit_log_chA_fri.txt`
      One chain = 32 concurrent models (the proven figure). A+B together would be 64.
- [ ] **Read `qhist` on chain A batch 1 before letting batches 2–5 run.** Chain C hit 95% of
      the 12 h walltime and fri 10 is far more fire — runtime effect unknown. Past ~11.5 h,
      split CSVs to one GCM per line rather than asking for more walltime
- [ ] Then chain B, then chain C
- [ ] **Do not put fri 60/120 back into `FRIS`** — it would clobber 936 verified replicates
- [ ] When processing this round: `generate_process_cmdfiles.sh` globs ALL scenario CSVs, so
      it now emits 60 treatments instead of 24. Needs a fri filter or a scoped run

---

## Earlier — 2026-09-13

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
- [x] **area_dom chain SUBMITTED 2026-09-15 as 7477443–7477467** (25 batches, landscapes
      01–05, first `Q` and 24 `H`). The five b05 tail batches are single-node **plain** jobs,
      not arrays — see NOTES.md, it changes the `afterokarray` plan
- [x] **Measured 2026-09-16 (7477443–7477448): 8.62–10.06 GB/step, 103–121 GB/node of 235,
      elapsed 26–41 min.** The 10–20 GB/step estimate was too high — memory has ~115 GB of
      headroom and **cores are the cap** (12 × 9 = 108 of 128, ceiling ~14 steps/node)
- [x] **area_dom landscape 01 COMPLETE** (7477443–7477447, all 156 runs). Landscape 02 under
      way: 7477448 done, 7477449 running
- [ ] **Two cheap speed-ups for the NEXT round, both one-liners, not applied mid-chain:**
      walltime 2 h → 1 h in `submit_chain_process.sh` (worst batch 41 min), and a larger
      `NODES_PER_JOB` in the generator. Justified because the chain is **queue-wait dominated
      between batches** — 7, 76 and 78 min from one batch ending to the next starting, against
      ~35 min of compute, so 25 batches is ~3 days at ~80% queueing. **324 concurrent workers
      is now proven** (a batch's 3 nodes start within 2–22 min of each other and overlap
      almost fully, 4 batches, no I/O errors), so a bigger batch is evidence-backed
- [x] **fire + KBDI gathered for ALL SIX landscapes** (2026-09-17): 936 replicates, 86 grids
      each, 0 failed. Doubles as a completeness check on the whole scenario round
- [ ] **Verify the archives before transferring** — the resume guard can hide a truncated
      tarball if a run is ever interrupted mid-`tar`:
      `find <root> -name kbdi.tar.gz | while read f; do gzip -t "$f" 2>/dev/null || echo "CORRUPT: $f"; done`
- [ ] Fix that guard properly: tar to a temp name, rename on success
- [ ] area_dom for landscape 06 — its iLand runs are done, so generate its batches and chain
      them; the per-landscape naming makes it additive, nothing else is regenerated
- [ ] A completeness checker for *processing* output — `check_cmdfile_complete.sh` parses the
      iLand runner signature and does not work on processing cmdfiles
- [ ] `afterokarray` — the helper is parked in `NOTES.md` (2026-09-13 entry), not in the
      scripts. **Only viable for the two MODEL submit scripts** (all their cmdfiles are 2+
      nodes). It would break the processing chain, whose b05 tail batches are single-node
      plain jobs, unless it detects array-ness per predecessor. Separate branch of work
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
