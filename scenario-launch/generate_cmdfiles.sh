#!/bin/bash
# Regenerate the Derecho cmdfiles for the scenario round.
#   bash scenario-launch/generate_cmdfiles.sh
#
# Matrix (scenario runs only -- the spinup snapshots are an input, not a run):
#   landscapes 01-06   ssp245, ssp370   fri 60, 120
#   onlysim=false  fire burns biomass           reps 1-12
#   onlysim=true   fire simulated, no effect    rep  1
#
# 6 lcp x 2 ssp x 2 fri x (12+1) reps = 312 lines = 936 model runs.
#
# Revised 2026-08-19: dropped ssp126, added the fri 60 / fri 120 contrast.
#
# Revised 2026-08-25 after the thread-scaling study (thread-scaling-test/report.md):
# onlysim=true drops from 3 reps to 1 and steps-per-node rises from 3 to 4. The 3
# reps existed because they "used up no additional resources" -- true only if a node
# is CPU-saturated, which the ~95% CPU reading appeared to show. It is not: that CPU
# was 3 steps x 256 threads contending for 128 cores, and the real limit is MEMORY,
# ~41-53 GB per step. Every extra step therefore consumes a real slot, so a rep that
# adds nothing scientifically is no longer free. onlysim=false carries replication.
#
# fri lives in its own CSV rather than as extra rows inside one. A line loops
# every row of its CSV, so folding both fri values into one file would put 6 rows
# = ~16 h of work on a line and overrun the 12 h walltime. Split this way a line
# stays 3 rows / ~8 h and the count of lines doubles instead of their duration.
#
# One line = one landscape x one ssp x one fri x one onlysim x one rep. Each line
# loops the three GCM rows of its CSV, so ~8 h of work inside a 12 h walltime.
#
# Every cmdfile must hold a multiple of STEPS_PER_NODE lines, or its last node runs
# fewer steps than it could. That still holds after 2026-08-25 even though 12+1 = 13
# is not itself a multiple of 4: lines are flattened before chunking, so a chain of
# 2 x 2 x 2 x 13 = 104 lines splits into 6 batches of 16 plus one of 8, and both 16
# and 8 are multiples of 4. The trailing job is simply smaller (2 nodes rather than
# 4), not under-filled. The check at the bottom re-verifies this if the matrix moves.
#
# The three chains are independent and split by landscape, so no two chains
# touch the same source directory; submit them one at a time to scale
# concurrency deliberately.
#
# Cmdfiles are written next to this script, which is also where submit_chain.sh
# looks for them, so it does not matter what directory you invoke this from.
set -euo pipefail

DIR="/glade/work/qasena/landscape_init_ak_can"   # path as seen on Derecho
RUNNER="${DIR}/run_iland_csv_cpxml_apptainer.sh"
YEARS=86
STEPS_PER_NODE=4          # must match --steps-per-node in submit_chain.sh
NODES_PER_JOB=4
BATCH=$(( NODES_PER_JOB * STEPS_PER_NODE ))
REPS_FALSE=12
REPS_TRUE=1
SSPS="245 370"            # ssp126 dropped from this round
FRIS="60 120"             # fire return interval contrast

chain_landscapes() {
    case "$1" in
        A) echo "01 02" ;;
        B) echo "03 04" ;;
        C) echo "05 06" ;;
    esac
}

out_dir=$(cd "$(dirname "$0")" && pwd)
rm -f "${out_dir}"/cmdfile_ch[ABC]_*.sh

total=0
for chain in A B C; do
    lines=()
    for n in $(chain_landscapes "$chain"); do
        xml="${DIR}/landscape_alaska_${n}/landscape_alaska_${n}_2015-2100scenario.xml"
        for ssp in $SSPS; do
            for fri in $FRIS; do
                for sim in false true; do
                    if [ "$sim" = "false" ]; then reps=$REPS_FALSE; else reps=$REPS_TRUE; fi
                    csv="${DIR}/scenario-launch/iland_scenarios_ssp${ssp}_sim${sim}_fri${fri}.csv"
                    for rep in $(seq 1 "$reps"); do
                        lines+=("bash ${RUNNER} ${xml} ${rep} ${rep} ${YEARS} ${csv}")
                    done
                done
            done
        done
    done

    n_lines=${#lines[@]}
    n_batches=$(( (n_lines + BATCH - 1) / BATCH ))
    sizes=""
    for ((b=0; b<n_batches; b++)); do
        f=$(printf "%s/cmdfile_ch%s_%02d.sh" "$out_dir" "$chain" $((b+1)))
        : > "$f"
        for ((i=b*BATCH; i<(b+1)*BATCH && i<n_lines; i++)); do
            echo "${lines[$i]}" >> "$f"
        done
        size=$(wc -l < "$f")
        sizes="${sizes}${size} "
        if (( size % STEPS_PER_NODE )); then
            printf "  WARNING: %s has %d lines, not a multiple of %d -- a node will be under-filled\n" \
                   "$(basename "$f")" "$size" "$STEPS_PER_NODE" >&2
        fi
    done
    printf "chain %s: %3d lines -> %d batches [ %s]\n" "$chain" "$n_lines" "$n_batches" "$sizes"
    total=$((total + n_lines))
done
printf "total: %d lines, %d model runs (3 GCMs per line)\n" "$total" "$((total * 3))"
