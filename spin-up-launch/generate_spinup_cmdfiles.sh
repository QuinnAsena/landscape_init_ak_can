#!/bin/bash
# Regenerate the Derecho cmdfiles for the 300-year spinup round.
#   bash spin-up-launch/generate_spinup_cmdfiles.sh
#
# Matrix: 6 landscapes x 9 replicates = 54 runs, one cmdfile per landscape.
#
# One line = one landscape x one rep. Unlike the scenario CSVs, which hold three
# GCM rows and so loop three model runs per line, iland_spinups.csv holds a
# single row (NorEsm2-MMssp126) -- so one line is exactly one 300-year run.
#
# The spinup produces two things the rest of the workflow needs:
#   1. snapshot/spinup_300.sqlite, written by snapShot() in saveWorkflow.js when
#      Globals.year == 300, which the scenario CSVs read via snapshot_file.
#   2. decadal kbdi grids plus the stand and saplingdetail outputs (years 260-300)
#      used to judge convergence.
# Both depend on saveWorkflow.js having exactly ONE onYearEnd declaration -- see
# the comment on that function before changing it.
#
# Batch size must stay a multiple of STEPS_PER_NODE or a node runs under-filled.
# 9 lines / 3 steps = 3 full nodes per batch. The check at the bottom re-verifies
# this if REPS changes.
#
# Cmdfiles are written next to this script, which is also where
# submit_chain_spinup.sh looks for them, so it does not matter what directory you
# invoke this from.
set -euo pipefail

DIR="/glade/work/qasena/landscape_init_ak_can"   # path as seen on Derecho
RUNNER="${DIR}/run_iland_csv_cpxml_apptainer.sh"
CSV="${DIR}/spin-up-launch/iland_spinups.csv"
YEARS=300
STEPS_PER_NODE=3          # must match --steps-per-node in submit_chain_spinup.sh
REPS=9
LANDSCAPES="01 02 03 04 05 06"

out_dir=$(cd "$(dirname "$0")" && pwd)
rm -f "${out_dir}"/cmdfile_spin_*.sh

total=0
for n in $LANDSCAPES; do
    xml="${DIR}/landscape_alaska_${n}/landscape_alaska_${n}_1950-1980spinup.xml"
    f="${out_dir}/cmdfile_spin_${n}.sh"
    : > "$f"
    for rep in $(seq 1 "$REPS"); do
        echo "bash ${RUNNER} ${xml} ${rep} ${rep} ${YEARS} ${CSV}" >> "$f"
    done

    size=$(wc -l < "$f")
    nodes=$(( (size + STEPS_PER_NODE - 1) / STEPS_PER_NODE ))
    if (( size % STEPS_PER_NODE )); then
        printf "  WARNING: %s has %d lines, not a multiple of %d -- a node will be under-filled\n" \
               "$(basename "$f")" "$size" "$STEPS_PER_NODE" >&2
    fi
    printf "landscape %s: %2d lines -> %d node(s)\n" "$n" "$size" "$nodes"
    total=$((total + size))
done
printf "total: %d lines, %d model runs (1 GCM row per line)\n" "$total" "$total"
