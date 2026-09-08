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
    *) echo "usage: bash scenario-launch/submit_chain.sh <A|B|C> [start_batch]" >&2; exit 1 ;;
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

# Optional second argument resumes a partial chain: `submit_chain.sh A 6` submits
# batches 6 onward only. With no argument the behaviour is exactly as before.
#
# WHY THIS EXISTS. On 2026-09-08 the Derecho maintenance window left job 7240530
# (chA_05) with its array parent stuck in state B even though all four sub-jobs had
# ended and all 48 model runs had finished cleanly. An afterok on a parent that never
# reaches a terminal state can never fire, so chA_06 and chA_07 were held forever.
# Re-running the whole chain was not an option: the runner has NO resume guard, so it
# would rm -rf and redo the five batches that had already completed.
#
# THE SHARP EDGE is not the slicing, it is the consequence. Batches before start_batch
# are skipped entirely, and the batch you start FROM is re-run in full. For a batch that
# died part-way that is correct -- the runner clears each scenario_dir first, and a
# resumed replicate would otherwise mix two fire realisations in one rep_N folder. For a
# batch that finished, it destroys good output. So start_batch must be the first batch
# that did NOT complete. Verify with:
#   bash analysis-scripts/check_cmdfile_complete.sh scenario-launch/cmdfile_ch<X>_<NN>.sh
start="${2:-1}"
case "$start" in
    ''|*[!0-9]*) echo "start_batch must be a positive integer, got: ${start}" >&2; exit 1 ;;
esac
(( start >= 1 && start <= ${#batches[@]} )) || {
    echo "start_batch ${start} out of range: chain ${chain} has ${#batches[@]} batch(es)" >&2
    exit 1; }
batches=("${batches[@]:start-1}")

# Echo the list before submitting, so a mistyped start_batch is visible now rather than
# after the jobs land.
if (( start > 1 )); then
    echo "resuming chain ${chain} from batch ${start} -- ${#batches[@]} batch(es) to submit:"
else
    echo "submitting chain ${chain} -- ${#batches[@]} batch(es):"
fi
for f in "${batches[@]}"; do
    echo "  $(basename "$f")  ($(grep -vc '^#' "$f") lines)"
done

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
