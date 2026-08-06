#!/bin/bash
# Regenerate the Derecho cmdfiles for the full scenario round.
#   bash generate_cmdfiles.sh
#
# Matrix (scenario runs only -- the spinup snapshots are an input, not a run):
#   landscapes 01-03   ssp126, ssp370           (ssp245 already complete)
#   landscapes 04-06   ssp126, ssp245, ssp370
#   onlysim=false  fire burns biomass           reps 1-12
#   onlysim=true   fire simulated, no effect    reps 1-4
#
# One line = one landscape x one ssp x one onlysim x one rep. Each line loops
# the three GCM rows of its CSV, so ~8 h of work inside a 12 h walltime.
#
# Batches are 12 lines = 4 nodes at --steps-per-node 3. The three chains are
# independent and split by landscape, so no two chains touch the same source
# directory; submit them one at a time to scale concurrency deliberately.
set -euo pipefail

DIR="/glade/work/qasena/landscape_init_ak_can"   # path as seen on Derecho
RUNNER="${DIR}/run_iland_csv_cpxml_apptainer.sh"
YEARS=86
BATCH=12
REPS_FALSE=12
REPS_TRUE=4

chain_landscapes() {
    case "$1" in
        A) echo "01 02" ;;
        B) echo "03 04" ;;
        C) echo "05 06" ;;
    esac
}

landscape_ssps() {
    case "$1" in
        01|02|03) echo "126 370" ;;
        04|05|06) echo "126 245 370" ;;
    esac
}

rm -f cmdfile_ch[ABC]_*.sh

total=0
for chain in A B C; do
    lines=()
    for n in $(chain_landscapes "$chain"); do
        xml="${DIR}/landscape_alaska_${n}/landscape_alaska_${n}_2015-2100scenario.xml"
        for ssp in $(landscape_ssps "$n"); do
            for sim in false true; do
                if [ "$sim" = "false" ]; then reps=$REPS_FALSE; else reps=$REPS_TRUE; fi
                csv="${DIR}/iland_scenarios_ssp${ssp}_sim${sim}.csv"
                for rep in $(seq 1 "$reps"); do
                    lines+=("bash ${RUNNER} ${xml} ${rep} ${rep} ${YEARS} ${csv}")
                done
            done
        done
    done

    n_lines=${#lines[@]}
    n_batches=$(( (n_lines + BATCH - 1) / BATCH ))
    for ((b=0; b<n_batches; b++)); do
        f=$(printf "cmdfile_ch%s_%02d.sh" "$chain" $((b+1)))
        : > "$f"
        for ((i=b*BATCH; i<(b+1)*BATCH && i<n_lines; i++)); do
            echo "${lines[$i]}" >> "$f"
        done
    done
    printf "chain %s: %3d lines -> %d batches\n" "$chain" "$n_lines" "$n_batches"
    total=$((total + n_lines))
done
printf "total: %d lines, %d model runs (3 GCMs per line)\n" "$total" "$((total * 3))"
