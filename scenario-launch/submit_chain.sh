#!/bin/bash
# Run from a Derecho login node:  bash scenario-launch/submit_chain.sh A
#
# Submits one chain of the current scenario round as a PBS afterok dependency
# chain -- each batch is held until the previous finishes. The three chains are
# independent and split by landscape, so they never touch the same source
# directory. Submit A first; once it is running cleanly add B, then C, to scale
# concurrency deliberately rather than in one jump.
#
#   A   landscapes 01, 02    8 batches    96 lines
#   B   landscapes 03, 04    8 batches    96 lines
#   C   landscapes 05, 06    8 batches    96 lines
#
# Each batch is 12 lines = 4 nodes at --steps-per-node 3, so 12 replicates run
# concurrently per chain (36 with all three chains live). Each line loops the
# three GCM rows of its CSV, ~8 h inside the 12 h walltime.
#
# Revised 2026-08-19 for the ssp245/ssp370 x fri 60/120 matrix at 9 reps
# (onlysim=false) and 3 (onlysim=true): 288 lines, 96 per chain, which divides
# into exactly 8 batches of 12 with no short trailing batch. Keep
# --steps-per-node here in step with STEPS_PER_NODE in generate_cmdfiles.sh,
# which checks that.
#
# NOTE: the runner has NO resume guard -- it `rm -rf`s each scenario_dir and
# re-runs, whether or not that replicate already finished. Anything on scratch
# sharing the same directory key (earlier ssp245 rounds included) is destroyed
# by a resubmission. Move it aside first if it is worth keeping.
#
# steps-per-node stays at 3 on MEMORY, not CPU. The ~95% node CPU at 3 x 40
# threads is not evidence the cores are needed: 3 x 40 = 120 threads on 128
# cores, and thread-scaling-test/report.md measured a replicate reaching its
# floor at 8 threads, so most of that CPU is threads contending. The real
# constraint is peak memory -- ~41-53 GB per step, so a 4th step takes the node
# from ~157 GB to ~209 GB against a 235 GB request.
#
# Regenerate the cmdfiles with generate_cmdfiles.sh after changing the matrix.
#
# Interrupted runs can leave temp XMLs behind in the landscape folders. Sweep
# them ONLY when no job of this round is active:
#   rm -f /glade/work/qasena/landscape_init_ak_can/landscape_alaska_0*/*_dbh2.5_onlysim*.xml
set -euo pipefail

chain="${1:-}"
case "$chain" in
    A|B|C) ;;
    *) echo "usage: bash scenario-launch/submit_chain.sh <A|B|C>" >&2; exit 1 ;;
esac

# --nthreads is placement metadata for launch_cf and does NOT reach iLand: the
# model takes its thread count from system.settings.threadCount, which the runner
# now sets (ILAND_THREADS, default 16). It was 40 here while iLand was actually
# running 256 threads per step -- that mismatch is what made the node look
# CPU-bound. Keep the two numbers in step so the next reader is not misled.
LAUNCH="launch_cf -A UCIE0001 -l walltime=12:00:00 --steps-per-node 3 --ppn 128 --nthreads 16 --mem 235GB -l job_priority=economy"
script_dir=$(cd "$(dirname "$0")" && pwd)

shopt -s nullglob
batches=("${script_dir}"/cmdfile_ch${chain}_*.sh)
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
