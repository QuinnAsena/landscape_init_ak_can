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
# START WITH A SINGLE LANDSCAPE, but for output volume rather than runtime or
# memory. Node packing is settled: --steps-per-node 3 is the configuration the
# earlier spinups were scaled up to and ran at. (An older note here cited
# --steps-per-node 1 --nthreads 128 from commit 78f793c; that was an early
# scaling test, not the production setting.)
#
# What the first batch is actually for: confirming saveWorkflow_spinup.js does
# its job. Check in the replicate output directory that
#     spinup_300.sqlite exists
#     kbdi/ holds ~31 grids (years 0, 10 ... 300), not 301
# The snapshot write was silently disabled between 2026-08-13 and 2026-08-19 by a
# second onYearEnd declaration shadowing the first, so it is worth an explicit
# look. This is also the first round using the split workflow files, so it proves
# iLand resolves the renamed script via <system><path><script>.
#
# WALLTIME 5 h, expect roughly 3-3.5 h. Do not read the local timing as the
# Derecho figure: a single 300-year spinup with these reduced outputs took 1 h 32 m
# locally with the whole machine to itself, while the comparable old Derecho
# spinup at 3 steps per node took 7 h 18 m with all outputs on. Comparing the two
# logs separates the two effects:
#
#   timer                    old (Derecho, 3/node)   new (local, alone)
#   ModelController:runYear        7h 17m 46s           1h 32m 02s
#   outputs                        4h 17m 30s              25m 31s
#   TreeOut::exec()                3h 32m 10s              absent
#   non-output remainder            ~3h 01m                ~1h 07m
#
# Disabling save_tree removed TreeOut::exec() entirely -- 82% of the old output
# time. But the non-output remainder still fell 3h 01m -> 1h 07m, and that 2.7x is
# node sharing and hardware, not outputs. So on Derecho at 3 steps per node,
# expect ~3 h of compute plus reduced output time -- call it 3-3.5 h. Walltime was
# cut 12 h -> 5 h on 2026-08-21 because a shorter request backfills sooner on
# Derecho; that leaves ~1.5 h of margin. A walltime kill is recoverable (no
# runner re-runs the replicate unconditionally), but it costs the queue
# wait, so check qhist elapsed on the first batch before chaining the rest. (Recoverable
# because the runner has no resume guard at all -- a resubmitted line always re-runs. The
# flip side is that it also clobbers replicates that DID finish.)
#
# Output volume is the thing to watch instead: that timing run produced a 25 GB
# output database plus a 10 GB snapshot per replicate, and 54 replicates of that
# is ~1.9 TB on scratch. Check the quota before chaining all six landscapes.
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

WALLTIME="10:00:00"
STEPS_PER_NODE=3          # must match STEPS_PER_NODE in generate_spinup_cmdfiles.sh
# --nthreads is placement metadata for launch_cf and does NOT reach iLand: the
# model takes its thread count from system.settings.threadCount, which the runner
# now sets (ILAND_THREADS, default 16). It was 40 here while iLand was actually
# running 256 threads per step -- that mismatch is what made the node look
# CPU-bound. Keep the two numbers in step so the next reader is not misled.
LAUNCH="launch_cf -A UCIE0001 -l walltime=${WALLTIME} --steps-per-node ${STEPS_PER_NODE} --ppn 128 --nthreads 16 --mem 235GB -l job_priority=economy"
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
