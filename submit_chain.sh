#!/bin/bash
# Run from Derecho login node: bash submit_chain.sh
# Submits 6 batches of 6 reps each as a PBS afterok dependency chain.
# Each batch waits for the previous to finish before starting.
set -euo pipefail

LAUNCH="launch_cf -A UCIE0001 -l walltime=18:00:00 --steps-per-node 3 --ppn 128 --nthreads 40 --mem 235GB -l job_priority=economy"
DIR="/glade/work/qasena/landscape_init_ak_can"

JID=$($LAUNCH ${DIR}/cmdfile_b01.sh)
echo "Batch 01 submitted: ${JID}"

for batch in b02 b03 b04 b05 b06; do
    JID=$($LAUNCH -W depend=afterok:${JID} ${DIR}/cmdfile_${batch}.sh)
    echo "Batch ${batch} submitted: ${JID}"
done

echo "All 6 batches queued. Verify with: qstat -u qasena"
