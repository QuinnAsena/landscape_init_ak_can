#!/bin/bash
# Run from a Derecho login node:
#   bash analysis-scripts/submit_chain_process.sh area_dom scenario
#   bash analysis-scripts/submit_chain_process.sh area_dom scenario 7   # resume from batch 7
#
# Chains the batch cmdfiles from generate_process_cmdfiles.sh, each held until the previous
# finishes. Batch size is set THERE (NODES_PER_JOB), not here: the number of LINES in a
# cmdfile is what sets concurrency, since every line can run at once.
#
# Only one batch runs at a time, so the first is measurable on its own -- submit, then
# qhist -j <first jobid>, and qdel the held successors if it looks wrong.
set -euo pipefail

analysis="${1:-}"
kind="${2:-}"
case "$kind" in scenario|spinup) ;; *)
    echo "usage: bash analysis-scripts/submit_chain_process.sh <analysis> <scenario|spinup> [start_batch]" >&2
    exit 1 ;;
esac

# Scenario writes all 86 years -> 9 workers per step, so 12 steps use 108 of 128 cores. The
# nodes are I/O-bound, not core-bound (CPU 20-41%, NOTES.md 2026-11-16) -- do not raise the
# steps on CPU headroom alone; more steps per node contend harder for scratch.
# Spinup writes only year >= 260 -> 5 workers, which is why 18 is fine there and not here.
# Keep in step with generate_process_cmdfiles.sh.
if [ "$kind" = "scenario" ]; then
    STEPS_PER_NODE=12; NTHREADS=9
else
    STEPS_PER_NODE=18; NTHREADS=5
fi
# WALLTIME IS 1 h, NOT 2. Measured elapsed for area_dom scenario batches is 0.44-0.68 h, i.e.
# 26-41 min (NOTES.md 2026-09-16), and the original hand-written cmdfile_process_*.sh
# invocations all used 1 h -- the 2 h this script shipped with on 2026-09-15 was never backed
# by a measurement. 41 of 60 min leaves ~19 min of margin, and the full 36-batch chain of
# 2026-11-13/14 confirmed it at the same 324 concurrent workers (worst node 40 min). If a batch
# ever lands near 50 min, qdel the held successors and resubmit at 2 h -- a processing batch
# only overwrites its own parquet, so re-running one costs nothing but time.
#
# PRIORITY: economy -- reverted 2026-11-24. Premium (1.5x charge) was set 2026-11-02 to cut
# queue wait while the allocation position was uncertain; that pressure is gone. The
# expected cost did NOT materialise: measured 2026-11-24 on economy, four batches ran
# back to back with inter-batch gaps of 2, 13 and 1 min, ~40 min a cycle -- no slower
# than premium's ~53 min (2026-11-13/14). A 1 h request backfills almost at once.
# One weekday-morning sample; September's ~2.9 h/cycle shows a busy spell can be slower.
LAUNCH="launch_cf -A UCEM0001 -l walltime=1:00:00 --steps-per-node ${STEPS_PER_NODE} --ppn 128 --nthreads ${NTHREADS} --mem 235GB -l job_priority=economy"

script_dir=$(cd "$(dirname "$0")" && pwd)
shopt -s nullglob
batches=("${script_dir}"/generated/cmdfile_${analysis}_${kind}_*_b*.sh)
start="${3:-1}"
batches=("${batches[@]:start-1}")

echo "submitting ${#batches[@]} batch(es):"
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
