#!/bin/bash
# Run from a Derecho login node.
#
#   bash spin-up-launch/submit_chain_spinup.sh 01      # ONE landscape -- test batch
#   bash spin-up-launch/submit_chain_spinup.sh         # all six, chained
#
# Submits the 300-year spinup round. Each cmdfile is one landscape's 9 replicates
# = 3 nodes at --steps-per-node 3. With no argument the six batches are chained
# with PBS afterok, so landscape 02 is held until 01 finishes.
#
# START WITH A SINGLE LANDSCAPE. Two things are unproven in this round and both
# show up in the first batch:
#
#   1. Node packing. The spinups that produced the current snapshots ran at
#      --steps-per-node 1 --nthreads 128, i.e. one replicate per node. This round
#      packs three. The 86-year scenarios already reach ~157 GB of the 235 GB
#      request at this packing, and a 300-year run carries a mature canopy with
#      more trees, so per-step memory will be higher. Check qhist for peak memory
#      before chaining the rest; if it is close to 235 GB, drop to
#      --steps-per-node 1 and set REPS/batching in generate_spinup_cmdfiles.sh
#      accordingly.
#
#   2. saveWorkflow.js. Its two onYearEnd declarations were merged on 2026-08-19
#      -- the later one had been silently shadowing snapShot() since 2026-08-13,
#      so spinups in that window would have written no snapshot. After the first
#      batch, confirm in the rep output directory:
#         spinup_300.sqlite exists
#         kbdi/ holds ~31 grids (years 0, 10 ... 300), not 301
#
# WALLTIME is 12 h for this test round, down from the 18 h used historically. The
# XMLs were regenerated on 2026-08-19 with tree/sapling/carbon/water outputs
# disabled, which should cut write volume enough to fit -- but 300 years at 40
# threads is roughly 9-10 h by the scenario scaling, so the margin is thin. If the
# first batch is killed on walltime rather than memory, raise this to 18:00:00
# rather than reducing the replicate count.
#
# The snapshot lands in the replicate's output directory, NOT in the landscape's
# snapshot/ folder:
#   $SCRATCH/output_ak_can/landscape_alaska_NN_1950-1980spinup/\
#     NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120/rep_<N>/spinup_300.sqlite
# Copy one chosen replicate per landscape to
#   landscape_alaska_NN/snapshot/spinup_300.sqlite
# which is the path the scenario CSVs reference. Existing snapshots there are
# 6-16 GB and dated May-July; move them aside first if worth keeping.
#
# Regenerate the cmdfiles with generate_spinup_cmdfiles.sh after changing the matrix.
set -euo pipefail

WALLTIME="12:00:00"
STEPS_PER_NODE=3          # must match STEPS_PER_NODE in generate_spinup_cmdfiles.sh
LAUNCH="launch_cf -A UCIE0001 -l walltime=${WALLTIME} --steps-per-node ${STEPS_PER_NODE} --ppn 128 --nthreads 40 --mem 235GB -l job_priority=economy"
script_dir=$(cd "$(dirname "$0")" && pwd)
lcp="${1:-}"

shopt -s nullglob
if [ -n "$lcp" ]; then
    case "$lcp" in
        0[1-6]) ;;
        *) echo "usage: bash spin-up-launch/submit_chain_spinup.sh [01|02|03|04|05|06]" >&2; exit 1 ;;
    esac
    batches=("${script_dir}/cmdfile_spin_${lcp}.sh")
    [ -f "${batches[0]}" ] || { echo "no cmdfile for landscape ${lcp}" >&2; exit 1; }
else
    batches=("${script_dir}"/cmdfile_spin_*.sh)
    (( ${#batches[@]} )) || { echo "no cmdfiles found -- run generate_spinup_cmdfiles.sh" >&2; exit 1; }
fi

JID=""
for f in "${batches[@]}"; do
    # launch_cf prints diagnostics before the job ID, hence tail -1.
    if [ -z "$JID" ]; then
        JID=$($LAUNCH "$f" | tail -1)
    else
        JID=$($LAUNCH -W depend=afterok:"${JID}" "$f" | tail -1)
    fi
    echo "$(basename "$f") submitted: ${JID}"
done
