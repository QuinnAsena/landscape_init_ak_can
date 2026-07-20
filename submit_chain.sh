#!/bin/bash
# Run from Derecho login node: bash submit_chain.sh
# Submits 3 batches (b01-b03: 9 reps each) as a PBS afterok dependency
# chain covering landscapes 01-03 of the current scenario set
# (iland_scenarios.csv), 9 reps per landscape: b01=landscape 01,
# b02=landscape 02, b03=landscape 03. Each batch waits for the previous
# to finish.
set -euo pipefail

LAUNCH="launch_cf -A UCIE0001 -l walltime=12:00:00 --steps-per-node 3 --ppn 128 --nthreads 40 --mem 235GB -l job_priority=economy"
DIR="/glade/work/qasena/landscape_init_ak_can"

JID=$($LAUNCH ${DIR}/cmdfile_b01.sh | tail -1)
echo "Batch b01 submitted: ${JID}"

for batch in b02 b03; do
    JID=$($LAUNCH -W depend=afterok:${JID} ${DIR}/cmdfile_${batch}.sh | tail -1)
    echo "Batch ${batch} submitted: ${JID}"
done
