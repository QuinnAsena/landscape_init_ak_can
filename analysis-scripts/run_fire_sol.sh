#!/bin/bash
# Run process_fire_sol.R over every FINISHED scenario replicate that has no burned_rids
# output yet. One invocation covers every landscape and treatment -- no cmdfiles, no chain.
#
#   bash analysis-scripts/run_fire_sol.sh [P] [FILTER]
#
#   P       parallel Rscript processes (default 4). Keep it small on a login node.
#   FILTER  optional extended regex matched against "<landscape> <treatment> <rep>",
#           e.g. 'onlysimtrue' or 'alaska_02_.*_fri60 3$'.
#
# The whole set on ONE compute node -- an economy 1 h request backfilled within minutes on
# 2026-11-24, while 6 h model batches waited days:
#
#   qsub -A UCEM0001 -q main -l select=1:ncpus=128:mem=235GB -l walltime=01:00:00 \
#        -l job_priority=economy -N fire_sol -j oe -- /bin/bash -lc \
#        "module purge; module load conda; conda activate my-r-4.4; \
#         bash /glade/work/qasena/landscape_init_ak_can/analysis-scripts/run_fire_sol.sh 64"
#
# WHY NOT A BASH LOOP OF Rscript ON THE LOGIN NODE. Every Rscript call reloads terra,
# arrow, dplyr and RSQLite -- seconds each, times ~2,400 replicates, serially -- and the
# crownkill grids are many small files per replicate, the Lustre metadata load that
# gather_fire_kbdi.R's header calls antisocial on a shared login node. On a compute node
# the same work runs 64-wide and finishes in minutes. 64 concurrent readers is mild next
# to the 324 area_dom workers that are proven on scratch.
#
# WHAT COUNTS AS FINISHED: the runner's .complete sentinel. A replicate that a model batch
# is still writing has no sentinel, so it is skipped rather than read half-written. Run
# this again after the batch ends to pick it up.
#
# RESUMABLE: a replicate is skipped when its log contains "--- Done ---", which
# process_fire_sol.R prints only after write_parquet returns. A run killed mid-write
# (walltime, Ctrl-C) has no such line and is redone next time, so re-running is always
# safe and never trusts a truncated parquet. Delete a replicate's fire_sol.log to force
# it to rerun.
#
# ISOLATED: one Rscript per replicate, so a stop() in one replicate fails that replicate
# only. Failures are listed at the end with the path to their log.
#
# SCOPE: scenario output only (landscape_*_2015-2100scenario). The depth limit means the
# processed/ tree and any tmp/ quarantine, which sit one level deeper, are never matched.
set -uo pipefail

P="${1:-4}"
FILTER="${2:-}"
# Must match data_path in process_fire_sol.R, which builds its paths independently.
ROOT="/glade/derecho/scratch/qasena/output_ak_can"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/process_fire_sol.R"
[ -d "$ROOT" ]   || { echo "no output root: $ROOT" >&2; exit 1; }
[ -f "$SCRIPT" ] || { echo "no script: $SCRIPT" >&2; exit 1; }
case "$P" in ''|*[!0-9]*|0) echo "P must be a positive integer, got: $P" >&2; exit 1 ;; esac

run_one() {
    local lcp=$1 trt=$2 n=$3
    local out="${ROOT}/${lcp}/processed/${trt}/rep_${n}/burned_rids"
    mkdir -p "$out"
    if Rscript "$SCRIPT" "$lcp" "$trt" "$n" > "${out}/fire_sol.log" 2>&1; then
        echo "ok   ${lcp} ${trt} ${n}"
    else
        echo "FAIL ${lcp} ${trt} ${n}   ${out}/fire_sol.log"
    fi
}
export -f run_one
export ROOT SCRIPT

# <landscape>/<treatment>/rep_<N>/.complete is exactly depth 4.
tasks=$(cd "$ROOT" && find . -mindepth 4 -maxdepth 4 -name .complete \
            -path './landscape_*_2015-2100scenario/*/rep_*/.complete' |
        awk -F/ '{ sub(/^rep_/, "", $4); print $2, $3, $4 }' | sort -V)

if [ -n "$FILTER" ]; then
    tasks=$(grep -E -- "$FILTER" <<< "$tasks" || true)
fi

todo=$(while read -r lcp trt n; do
           [ -n "$lcp" ] || continue
           grep -qs -e '--- Done ---' \
               "${ROOT}/${lcp}/processed/${trt}/rep_${n}/burned_rids/fire_sol.log" ||
               echo "$lcp $trt $n"
       done <<< "$tasks")

n_all=$(grep -c . <<< "$tasks")
n_todo=$(grep -c . <<< "$todo")
echo "finished replicates matched: ${n_all}   already done: $((n_all - n_todo))   to run: ${n_todo} at P=${P}"
[ "$n_todo" -gt 0 ] || exit 0

res=$(mktemp)
xargs -P "$P" -n 3 bash -c 'run_one "$@"' _ <<< "$todo" | tee "$res"

echo
echo "ok: $(grep -c '^ok' "$res")   FAILED: $(grep -c '^FAIL' "$res")"
grep '^FAIL' "$res"
rm -f "$res"
