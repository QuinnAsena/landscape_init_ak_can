#!/bin/bash
# Run from Derecho login node: bash submit_chain.sh
# Submits 10 batches of 3 reps each (1 node) as a PBS afterok dependency chain.
# Each batch waits for the previous to finish before starting.
set -euo pipefail

LAUNCH="launch_cf -A UCIE0001 -l walltime=18:00:00 --steps-per-node 3 --ppn 128 --nthreads 40 --mem 235GB -l job_priority=economy"
DIR="/glade/work/qasena/landscape_init_ak_can"

JID=$($LAUNCH ${DIR}/cmdfile_s01.sh | tail -1)
echo "Batch s01 submitted: ${JID}"

for batch in s02 s03 s04 s05 s06 s07 s08 s09 s10; do
    JID=$($LAUNCH -W depend=afterok:${JID} ${DIR}/cmdfile_${batch}.sh | tail -1)
    echo "Batch ${batch} submitted: ${JID}"
done

echo "All 10 batches queued. Verify with: qstat -u qasena"
