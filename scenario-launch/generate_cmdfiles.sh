#!/bin/bash
# Regenerate the Derecho cmdfiles for the scenario round.
#   bash scenario-launch/generate_cmdfiles.sh
#
# Matrix (scenario runs only -- the spinup snapshots are an input, not a run):
#   landscapes 01-06   ssp245, ssp370   fri 10, 15, 30
#   onlysim=false  fire burns biomass           reps 1-12
#   onlysim=true   fire simulated, no effect    rep  1
#
# 6 lcp x 2 ssp x 3 fri x (12+1) reps = 468 lines.
# Model runs are NOT 3 per line any more -- see the GCM note below -- so the round
# is 234 ssp370 lines x 3 GCMs + 234 ssp245 lines x 2 GCMs = 1170 model runs.
#
# Revised 2026-10-20: NorEsm2-MM is EXCLUDED FROM ssp245 ONLY, by deleting its row
# from the six ssp245 fri10/15/30 CSVs. Its downscaled ssp245 climate has three
# corrupt source files, one of which (vp-2066) leaves vpd NULL for a whole year
# inside the 2015-2100 window -- see the 2026-10-16 NOTES entry. TaiESM1 and
# UKESM1-0-LL under ssp245 are clean and are kept, as is all of ssp370 including
# NorEsm2-MM. An earlier version of this round dropped ssp245 wholesale, which
# needlessly discarded two good GCMs and the SSP contrast with it.
#
# CONSEQUENCE: ssp245 lines now loop TWO CSV rows, ssp370 lines three. An ssp245
# line is therefore about two thirds the work -- roughly 5-7 h against 8-11 h --
# which widens the 12 h walltime margin for half the round. The fri 60/120 CSVs are
# untouched and still carry all three GCMs, so this round's ssp245 has one fewer GCM
# than the completed one.
#
# Revised 2026-08-19: dropped ssp126, added the fri 60 / fri 120 contrast.
#
# Revised 2026-10-15: FRIS moved 60/120 -> 10/15/30 for the short-interval round.
# fri 60 and 120 are COMPLETE (936 runs, verified) and must NOT be put back into FRIS
# to "have them all in one place" -- `scenario_id` is keyed on fri, so re-running those
# values would land on the existing output directories, and the runner clears each
# scenario_dir unconditionally. That would destroy 936 verified replicates. The five-way
# contrast lives on scratch across two rounds, not in one cmdfile set.
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
# every row of its CSV, so folding the fri values into one file would put 9 rows
# = ~24 h of work on a line and overrun the 12 h walltime several times over. Split
# this way a line stays 3 rows / ~8 h and the count of lines grows instead.
#
# One line = one landscape x one ssp x one fri x one onlysim x one rep. Each line
# loops the three GCM rows of its CSV, so ~8 h of work inside a 12 h walltime.
#
# Every cmdfile must hold a multiple of STEPS_PER_NODE lines, or its last node runs
# fewer steps than it could. That still holds even though 12+1 = 13 is not itself a
# multiple of 4: lines are flattened before chunking, so the single chain of
# 6 x 2 x 3 x 13 = 468 lines splits into 14 batches of 32 plus one of 20, and both 32
# and 20 are multiples of 4. The trailing job is simply smaller (5 nodes rather than
# 8), not under-filled. The check at the bottom re-verifies this if the matrix moves.
#
# (The ssp370-only variant briefly tried on 2026-10-20 gave 78 lines a chain, which is
# NOT divisible by 4 and warned every time. Restoring ssp245 restored the clean split
# -- a reason to prefer an even number of ssp x fri combinations.)
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
# 4 -> 8 on 2026-09-13. 32 concurrent steps is MEASURED, not extrapolated: on 2026-09-09
# chB_04 (7314029) and chA_06 (7349729) overlapped for ~6h20m with all 8 nodes busy, and
# cost nothing -- 7.08-9.96 h elapsed and 137-166 GB/node against 8.06-9.91 h and
# 137-174 GB for a job running alone. Scratch I/O is the only resource two jobs share and
# it did not bite. This is a batching change only: launch_cf derives the array size from
# lines / steps-per-node and PBS schedules each subjob as its own 1-node allocation, so a
# 32-line cmdfile is `-J 0-7`, eight independently scheduled nodes, NOT an 8-node
# reservation. Queue wait should not worsen; the chain just has 4 turnarounds instead of 7.
NODES_PER_JOB=8
BATCH=$(( NODES_PER_JOB * STEPS_PER_NODE ))
REPS_FALSE=12
REPS_TRUE=1
SSPS="245 370"            # ssp126 dropped; NorEsm2-MM excluded from ssp245 CSVs -- see header
FRIS="10 15 30"           # short-interval round; 60 and 120 are DONE -- see header

# ONE CHAIN covering all six landscapes, as of 2026-10-20. Previously three chains of
# two landscapes each (A 01/02, B 03/04, C 05/06), submitted one at a time.
#
# Why the split existed, and why it no longer earns its keep: at `economy` the queue
# wait was so long that submitting the next chain while the current one ran meant it
# arrived roughly as that one finished -- accidental staggering that held concurrency
# near 32 without anyone managing it. At `premium` that feedback is gone, so holding 32
# would mean deliberately waiting for each chain to finish and submitting the next by
# hand. One chain self-sequences instead: 15 batches, afterok end to end, submit once.
#
# Total time is UNCHANGED -- one chain of 15 batches and three chains of 5 run
# back-to-back are the same ~141 h of compute. The split only ever bought optionality.
#
# WHAT IS GIVEN UP, so it is a known trade and not a surprise:
#   - A stall strands everything behind it. The 2026-09-08 stuck array parent stranded
#     2 batches; here it could strand up to 14. `start_batch` is the recovery, and it
#     matters more now, not less -- see submit_chain.sh.
#   - No clean way to add parallelism mid-flight. With separate chains a second could
#     be submitted alongside the first (disjoint landscapes, no shared source dirs);
#     within one chain, start_batch would re-run batches the running stream will reach.
# To go back, restore the three-way case below and set CHAINS="A B C".
CHAINS="A"
chain_landscapes() {
    case "$1" in
        A) echo "01 02 03 04 05 06" ;;
    esac
}

out_dir=$(cd "$(dirname "$0")" && pwd)
rm -f "${out_dir}"/cmdfile_ch[ABC]_*.sh

total=0
runs=0        # actual model runs, accumulated from each CSV's GCM row count
for chain in $CHAINS; do
    lines=()
    for n in $(chain_landscapes "$chain"); do
        xml="${DIR}/landscape_alaska_${n}/landscape_alaska_${n}_2015-2100scenario.xml"
        for ssp in $SSPS; do
            for fri in $FRIS; do
                for sim in false true; do
                    if [ "$sim" = "false" ]; then reps=$REPS_FALSE; else reps=$REPS_TRUE; fi
                    csv="${DIR}/scenario-launch/iland_scenarios_ssp${ssp}_sim${sim}_fri${fri}.csv"
                    # Count the CSV's GCM rows rather than assuming three. Since
                    # 2026-10-20 the ssp245 CSVs carry two (NorEsm2-MM excluded), so a
                    # fixed multiplier would misreport the size of the round.
                    local_csv="${out_dir}/$(basename "$csv")"
                    [ -f "$local_csv" ] || { echo "  ERROR: missing CSV $(basename "$csv")" >&2; exit 1; }
                    gcm_rows=$(( $(grep -vc '^[[:space:]]*$' "$local_csv") - 1 ))
                    for rep in $(seq 1 "$reps"); do
                        lines+=("bash ${RUNNER} ${xml} ${rep} ${rep} ${YEARS} ${csv}")
                        runs=$(( runs + gcm_rows ))
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
printf "total: %d lines, %d model runs (GCM rows counted per CSV, not assumed)\n" "$total" "$runs"
