# TODO

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
