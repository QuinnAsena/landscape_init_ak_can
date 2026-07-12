#!/bin/bash
# Run from Derecho login node: bash submit_chain.sh
# Submits 5 batches (b01-b05: 6 reps each) as a PBS afterok dependency
# chain covering landscapes 01-03 of the new scenario set
# (iland_scenarios.csv). Landscape 01 reps 1-3 already ran as a test, so
# b01 starts at rep 4. Each batch waits for the previous to finish.
# The remaining 3-rep leftover (landscape 03 reps 10-12) doesn't divide
# evenly into steps-per-node=6, so it is submitted separately via
# cmdfile_runreplicates_csv_iland2.1.sh with its own steps-per-node=3.
set -euo pipefail

LAUNCH="launch_cf -A UCIE0001 -l walltime=18:00:00 --steps-per-node 6 --ppn 128 --nthreads 20 --mem 235GB -l job_priority=economy"
DIR="/glade/work/qasena/landscape_init_ak_can"

JID=$($LAUNCH ${DIR}/cmdfile_b01.sh | tail -1)
echo "Batch b01 submitted: ${JID}"

for batch in b02 b03 b04 b05; do
    JID=$($LAUNCH -W depend=afterok:${JID} ${DIR}/cmdfile_${batch}.sh | tail -1)
    echo "Batch ${batch} submitted: ${JID}"
done
