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

# Scenario writes all 86 years -> 9 workers per step, so cores cap it near 14 steps/node.
# Spinup writes only year >= 260 -> 5 workers, which is why 18 is fine there and not here.
# Keep in step with generate_process_cmdfiles.sh.
if [ "$kind" = "scenario" ]; then
    STEPS_PER_NODE=12; NTHREADS=9
else
    STEPS_PER_NODE=18; NTHREADS=5
fi
LAUNCH="launch_cf -A UCIE0001 -l walltime=2:00:00 --steps-per-node ${STEPS_PER_NODE} --ppn 128 --nthreads ${NTHREADS} --mem 235GB -l job_priority=economy"

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
