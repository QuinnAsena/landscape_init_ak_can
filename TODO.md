# TODO

## In flight — 2026-10-20: fri 10/15/30 round, NorEsm2-MM out of ssp245, premium priority

- [x] **NorEsm2-MM removed from the six ssp245 fri10/15/30 CSVs only.** TaiESM1 and
      UKESM1-0-LL under ssp245 are clean and kept; ssp370 keeps all three GCMs. The
      fri 60/120 CSVs are untouched and still carry three
- [x] `job_priority=economy` → `premium` in `scenario-launch/submit_chain.sh` (1.5× charge,
      bought for queue position with the deadline close)
- [x] **Collapsed to ONE chain, one submission** — `CHAINS="A"` and `chain_landscapes A`
      returns all six landscapes. 468 lines → **15 batches (14 × 32 + 20)**, afterok end to
      end. Same total time as three chains back-to-back (~141 h); it just removes the two
      manual handoffs that premium made necessary
- [x] Verified **lossless** against the committed three-chain version — same 468 lines,
      only regrouped. 0 blanks, every batch divisible by 4, 432 simfalse / 36 simtrue,
      NorEsm2-MM in 6/6 ssp370 CSVs and 0/6 ssp245, batch order correct across 09 → 10
- [x] Generator now **counts each CSV's GCM rows** instead of assuming 3 — the old
      `total * 3` would have over-reported this round by 234 runs
- [x] **SUBMITTED 2026-10-20: 7884487–7884503**, 15 batches, first `Q` and 14 `H`.
      Job IDs are **not consecutive** — 7884496 and 7884498 went to other users, so
      chA_10 = 7884497 and chA_11 = 7884499. The submit echo is the only reliable mapping
- [x] **Batch 2 measured: 11.53 h = 96% of walltime, 28 min spare.** Diagnosis: the long pole
      is **`onlysim=true`**, not fri. Nodes of 4× fri10 simfalse ran 6.3–6.5 h; the otherwise
      identical node carrying one fri10 **simtrue** line ran 11.53 h. `onlysim=true` simulates
      fire but kills nothing, so the stand keeps every tree. More fire is *faster* when it
      burns (fri10 simfalse 6.3–6.5 h < fri15 simfalse 7.6–8.0 h), slower when it doesn't
- [x] **RESOLVED 2026-10-22: UCAR raised all remaining jobs to 16 h.** No resubmission or CSV
      splitting needed. Batch 3 then confirmed the model — its two ssp370 simtrue nodes ran
      11.20 h (fri15) and 11.38 h (fri30) against 11.1–11.5 h predicted from fri10's 11.52 h
- [ ] **DEADLINE AT RISK (2026-10-26, 7 of 15 done).** Queue gaps jumped **4.7×** exactly when
      the 16 h walltime was applied: 2.30/8.50/0.95 h at a 12 h request, then
      10.60/21.20/22.70 h at 16 h. A 16 h request backfills far worse. At ~27–31 h per cycle
      the remaining 8 batches finish **3–5 Nov, missing 31 Oct by 3–5 days**. Need ~18 h per
      cycle; the pre-extension rate was ~13.5 h
- [x] **`qalter -l walltime=12:00:00 '<jobid>[]'` works as the user** (only *raising* needs an
      admin). Quote the ID — `[]` is a shell glob. Takes ~a minute to show in `qstat`
- [x] **Hypothesis looks confirmed:** 7884494 had queued ~12 h at 16 h and started almost
      immediately once lowered to 12 h. Before/after/before reversal, so not just a busy cluster
- [x] **Four lowered to 12 h** (7884494/95/97/99 — lcp03/04, longest line ≤10.4 h).
      **7884500–7884503 left at 16 h on purpose**
- [x] **Full review of all 336 steps on record (2026-10-26).** simtrue is *nearly* fri-independent
      but **+4.3% from fri60 to fri10**; a fri60 baseline × 1.043 predicts fri10 within 1%
      (validated out-of-sample on lcp02 and lcp03). **lcp05 is the most expensive landscape, not
      lcp01** — 11.35 h at fri60, so **~11.84 h at fri10, only ~10 min under a 12 h wall**
- [x] **Walltime–backfill hypothesis RETRACTED (2026-10-27).** 7884495 sat at a 12 h request and
      still waited ≥14 h. The 7884494 reversal was coincidence; cluster load explains the series
      better (short gaps 20–22 Oct, worst gaps over the 24–25 Oct weekend, regardless of request)
- [x] **DECISION: leave the chain as-is, mop up the remainder on another project ID.** Single
      chain lands 3–4 Nov vs a 31 Oct end. Parallelising into 3 chains would land ~30 Oct but
      means **64–96 concurrent models against a measured-safe 32** — untested I/O risk, and
      contention could push the lcp05 simtrue lines past their wall
- [ ] **For the mop-up:** (a) `-A UCIE0001` is hard-coded in `submit_chain.sh` — change it for a
      new project ID; (b) the existing `cmdfile_chA_*.sh` are reusable as-is, use
      `check_cmdfile_complete.sh` to find what finished then `submit_chain.sh A <start_batch>`
      (the batch you start FROM re-runs in full); (c) lcp05's simtrue lines (chA_12/13) still
      need 16 h or a one-GCM-per-line split — they project to 11.84 h against a 12 h wall
- [ ] **Watch the next gaps.** If cycles return to ~13.5 h, the remaining batches land ~30 Oct
      with about a day of margin and the parallel split is not needed. If gaps stay long,
      split batches 12–15 into a second chain
- [x] **Landscapes differ ~30%, and only lcp01 is slow.** Per run, lcp02 is 0.69–0.77× lcp01
      across every configuration; its ssp370 simtrue lines ran 8.66–8.89 h vs lcp01's 11.52 h.
      Last round's chain A combined 01+02 so this was invisible. Batch 4's fast 5.95 h is fully
      explained: all lcp02, 21 of 32 lines ssp245 (2 GCM rows), at fri15/fri30
- [ ] **If it slips, split the tail:** `qdel` batches 11–15 (7884499–7884503, landscapes
      05/06), regenerate as a separate chain and run it in parallel — disjoint scenario_dirs,
      so no clobber risk. Finishes both streams in ~5 days at 64 concurrent models (2× the
      measured-safe 32)
- [x] **CONFIRMED from `stdout-7884488.desched1`:** step-00020 = ssp370 fri10 onlysim=true,
      **11.52 h**, which alone set its node's 11.53 h. Per model run: simtrue **3.71–3.84 h
      regardless of fri**, simfalse 2.02 / 2.45 / 2.90 h at fri 10 / 15 / 30 (more fire =
      faster, monotonic). simtrue is effectively a no-fire run, so fri barely touches it
- [ ] **Risk set is 18 lines, not 6** — every ssp370 simtrue line is ~11.1–11.5 h, not just
      the fri10 ones, across 10 of the 13 remaining batches (chA_03, 05, 07, 08, 09, 10, 12,
      13, 14, 15). 7884491 (batch 5) is still the earliest warning
- [ ] **Everything simfalse is safe in 12 h** (slowest measured 8.00 h; ssp370 fri30 simfalse
      projects to ~8.7 h). So if the 16 h request is refused, only the **18 ssp370 simtrue
      lines** need splitting to one GCM per line — 54 lines at ~3.8 h each
- [ ] **If one is killed:** the chain stalls (subjob non-zero → `afterok` never fires). Fix by
      splitting the simtrue CSVs to one GCM per line (~3.8 h instead of ~11.5) and resuming
      with `start_batch` at the first incomplete batch — which is re-run in full
- [ ] **If the chain stalls, `start_batch` matters more now** — a stuck array parent can
      strand up to 14 batches rather than 4. Find the first batch that did not complete and
      resume from it; the batch you resume FROM is re-run in full
- [ ] **Raise the processing chain to premium too?** `submit_chain_process.sh` is still on
      economy, so area_dom for this round will queue at the old priority
- [ ] **Drop back to economy once the deadline passes** — no reason to pay 1.5× afterwards

---

## Earlier — 2026-10-16: corrupt NorEsm2-MM/ssp245 climate files

- [x] Diagnosed: **three bad source `.nc` files** under `Landscapes/Downscaled NorEsm2-MM/ssp245/`
      — `tasmin-1958` (48 KB stub, no CRS), `vp-2066` (full size, no CRS, **all zeros**),
      `vp-1958` (full size, valid CRS, **all-NA over the domain**). Audited all 54
      landscape×GCM×SSP combinations: **only this one is affected**
- [x] Report to Lora Murphy written as a Claude Doc — exact paths, per-file defect,
      reproduction steps, and why size/open checks pass two of the three
- [x] Three guards added and verified against a fixture: script 03 now `warning()`s on failure
      even at the default `logs = FALSE`; script 04 asserts all five variables share a year set,
      and refuses to write a database containing any NA
- [ ] **Send the report to Lora** (and decide on the last paragraph — see the doc comment)
- [ ] **Winslow:** does one year of missing vpd (2066) warrant re-running the completed
      NorEsm2-MM/ssp245 replicates? 156 of 936 runs. **No gap-filling** — decided
- [ ] If re-exported: re-run script 03 for that combination with `logs = TRUE`, confirm all
      five variables reach 151 `.txt`, then rebuild the six databases — the new guards will
      refuse to compile until it is genuinely clean

---

## Earlier — 2026-10-15: short-interval fire round (fri 10, 15, 30)

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
