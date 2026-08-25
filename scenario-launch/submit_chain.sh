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
# A full batch is 16 lines = 4 nodes at --steps-per-node 4, so 16 replicates run
# concurrently per chain (48 with all three chains live). Each line loops the
# three GCM rows of its CSV, ~8 h inside the 12 h walltime -- but see the note on
# contention below.
#
# Revised 2026-08-25: 12 reps (onlysim=false) and 1 (onlysim=true) -> 312 lines,
# 104 per chain, which chunks into 6 batches of 16 plus one of 8. Both are
# multiples of 4, so no node is under-filled; the last job is just smaller. Keep
# --steps-per-node here in step with STEPS_PER_NODE in generate_cmdfiles.sh,
# which checks that.
#
# NOTE: the runner has NO resume guard -- it `rm -rf`s each scenario_dir and
# re-runs, whether or not that replicate already finished. Anything on scratch
# sharing the same directory key (earlier ssp245 rounds included) is destroyed
# by a resubmission. Move it aside first if it is worth keeping.
#
# steps-per-node is a MEMORY question, not a CPU one, and it moved 3 -> 4 on
# 2026-08-25. The ~95% node CPU at the old setting was never evidence the cores
# were needed: threadCount was inherited as -1, so each step took all 256 logical
# processors and three steps contended for 128 cores. A replicate stops getting
# faster at 8 threads (thread-scaling-test/report.md), and threadCount is now set
# explicitly to 16 by the runner. The binding limit is peak memory at ~41-53 GB
# per step, so 4 steps is ~165-210 GB against a 235 GB request -- it fits, but
# check qhist resources_used.mem on the first job rather than trusting that.
#
# WATCH THE WALLTIME. The ~8 h/line figure was measured at 3 steps per node. Four
# instances contend more for memory bandwidth; locally three concurrent instances
# ran 36% slower per instance than one alone. Derecho has more cores and memory
# channels so it should be milder, but if a line drifts toward 11 h the 12 h
# walltime gets tight. Check qhist elapsed on the first chain-A job.
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
LAUNCH="launch_cf -A UCIE0001 -l walltime=12:00:00 --steps-per-node 4 --ppn 128 --nthreads 16 --mem 235GB -l job_priority=economy"
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
