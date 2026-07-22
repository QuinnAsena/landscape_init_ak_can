#!/bin/bash
# Run from Derecho login node: bash submit_chain.sh
# Submits the remaining 2 batches (b02-b03: 9 reps each) as a PBS afterok
# dependency chain covering landscapes 02-03 of the current scenario set
# (iland_scenarios.csv), 9 reps per landscape: b02=landscape 02,
# b03=landscape 03. b01 (landscape 01) already completed, so this chain
# starts fresh at b02. Each batch waits for the previous to finish.
set -euo pipefail

LAUNCH="launch_cf -A UCIE0001 -l walltime=10:00:00 --steps-per-node 3 --ppn 128 --nthreads 40 --mem 235GB -l job_priority=economy"
DIR="/glade/work/qasena/landscape_init_ak_can"

JID=$($LAUNCH ${DIR}/cmdfile_b02.sh | tail -1)
echo "Batch b02 submitted: ${JID}"

JID=$($LAUNCH -W depend=afterok:${JID} ${DIR}/cmdfile_b03.sh | tail -1)
echo "Batch b03 submitted: ${JID}"
