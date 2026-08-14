#!/bin/bash
# Run from a Derecho login node:  bash submit_chain.sh A
#
# Submits one chain of the current scenario round as a PBS afterok dependency
# chain -- each batch is held until the previous finishes. The three chains are
# independent and split by landscape, so they never touch the same source
# directory. Submit A first; once it is running cleanly add B, then C, to scale
# concurrency deliberately rather than in one jump.
#
#   A   landscapes 01, 02    8 batches    90 lines
#   B   landscapes 03, 04    8 batches    90 lines
#   C   landscapes 05, 06    8 batches    90 lines
#
# Each batch is 12 lines = 4 nodes at --steps-per-node 3, so 12 replicates run
# concurrently per chain (36 with all three chains live). Each line loops the
# three GCM rows of its CSV, ~8 h inside the 12 h walltime.
#
# Every chain ends on a 6-line batch, a multiple of --steps-per-node, so it
# fills 2 nodes rather than leaving one under-used. Keep --steps-per-node here
# in step with STEPS_PER_NODE in generate_cmdfiles.sh, which checks that.
#
# NOTE: the runner clears each scenario_dir before running a replicate that has
# no .complete sentinel. Output on scratch from the earlier ssp245 rounds has no
# sentinel and shares the same directory key, so submitting will overwrite it.
# Move it aside first if it is worth keeping for comparison.
#
# steps-per-node stays at 3: at 3 x 40 threads the node already reports ~95%
# CPU, so packing a 4th step yields the same lines per node-hour while raising
# peak memory from ~157 GB to ~209 GB against a 235 GB request.
#
# Regenerate the cmdfiles with generate_cmdfiles.sh after changing the matrix.
#
# Interrupted runs can leave temp XMLs behind in the landscape folders. Sweep
# them ONLY when no job of this round is active:
#   rm -f landscape_alaska_0*/*_dbh2.5_onlysim*.xml
set -euo pipefail

chain="${1:-}"
case "$chain" in
    A|B|C) ;;
    *) echo "usage: bash submit_chain.sh <A|B|C>" >&2; exit 1 ;;
esac

LAUNCH="launch_cf -A UCIE0001 -l walltime=12:00:00 --steps-per-node 3 --ppn 128 --nthreads 40 --mem 235GB -l job_priority=economy"
DIR="/glade/work/qasena/landscape_init_ak_can"

shopt -s nullglob
batches=("${DIR}"/cmdfile_ch${chain}_*.sh)
(( ${#batches[@]} )) || { echo "no cmdfiles found for chain ${chain}" >&2; exit 1; }

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
