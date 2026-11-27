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
# RESUMABLE: a replicate is skipped when its burned_rids.parquet exists. That is safe
# ONLY because process_fire_sol.R writes to burned_rids.parquet.tmp and renames, so the
# final name never holds a truncated file -- a run killed mid-write (walltime, Ctrl-C)
# leaves just the .tmp and is redone next time. Keep that write-then-rename if the R
# script is edited. To force replicates to rerun (e.g. after changing the R logic),
# delete their burned_rids.parquet.
#
# LOGS ARE KEPT ONLY FOR FAILURES. Each run logs to a temp file that is deleted on
# success and moved to burned_rids/fire_sol.log on failure -- no clutter from ~2,400
# successes, and a failure's log is there first time without a rerun. A success also
# removes any fire_sol.log left by an earlier failure. KEEP_LOGS=1 keeps every log:
#   KEEP_LOGS=1 bash analysis-scripts/run_fire_sol.sh 2 '<filter>'
#
# ISOLATED: one Rscript per replicate, so a stop() in one replicate fails that replicate
# only. Failures are listed at the end with the path to their log.
#
# ENVIRONMENT: Rscript is whatever is on PATH. On a login node, `module load conda;
# conda activate my-r-4.4` first -- without it every replicate fails (2026-11-27). The
# qsub line above activates it itself.
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
    local log
    log=$(mktemp)
    if Rscript "$SCRIPT" "$lcp" "$trt" "$n" > "$log" 2>&1; then
        if [ "$KEEP_LOGS" = 1 ]; then
            mv -f "$log" "${out}/fire_sol.log"
        else
            rm -f "$log" "${out}/fire_sol.log"
        fi
        echo "ok   ${lcp} ${trt} ${n}"
    else
        mkdir -p "$out"
        mv -f "$log" "${out}/fire_sol.log"
        echo "FAIL ${lcp} ${trt} ${n}   ${out}/fire_sol.log"
    fi
}
KEEP_LOGS="${KEEP_LOGS:-0}"
export -f run_one
export ROOT SCRIPT KEEP_LOGS

# <landscape>/<treatment>/rep_<N>/.complete is exactly depth 4.
tasks=$(cd "$ROOT" && find . -mindepth 4 -maxdepth 4 -name .complete \
            -path './landscape_*_2015-2100scenario/*/rep_*/.complete' |
        awk -F/ '{ sub(/^rep_/, "", $4); print $2, $3, $4 }' | sort -V)

if [ -n "$FILTER" ]; then
    tasks=$(grep -E -- "$FILTER" <<< "$tasks" || true)
fi

todo=$(while read -r lcp trt n; do
           [ -n "$lcp" ] || continue
           [ -f "${ROOT}/${lcp}/processed/${trt}/rep_${n}/burned_rids/burned_rids.parquet" ] ||
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
