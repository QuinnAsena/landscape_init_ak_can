#!/bin/bash
# Thread-scaling benchmark for iLand, plus the .txt vs .tif input trial.
#   bash thread-scaling-test/run_thread_scaling.sh            # threads sweep
#   bash thread-scaling-test/run_thread_scaling.sh nooutput   # compute only, writers off
#   bash thread-scaling-test/run_thread_scaling.sh geotiff    # txt vs tif at one thread count
#
# Run setup_sandbox.sh first. Run nothing else on the machine while this is going.
#
# WHAT IS BEING MEASURED, and why it is not just wall time: if output writing is
# single-threaded (very likely -- SQLite writes through one connection, and the
# old Derecho spinup spent 4h17m of a 7h18m run in `outputs`) then total time is
# serial_output + parallel_compute, and only the second term responds to threads.
# iLand's own timer block separates them, so parse_timers.R reads the split
# directly rather than fitting Amdahl to a black box.
#
# THE FIXED SEED IS NOT OPTIONAL. The XML ships randomSeed=0, which is
# non-reproducible: every run would burn differently, giving different tree
# mortality and therefore a different amount of compute. The comparison would be
# between different workloads. Any non-zero value fixes it.
#
# THREADS STAY <= 32. This machine is a Threadripper 7970X: 32 physical cores, 64
# logical. Derecho's 40 threads are 40 physical Milan cores, so anything above 32
# here measures SMT behaviour that does not exist on a Derecho node.
set -euo pipefail

SANDBOX="${ILAND_SANDBOX:-D:/quinn/iland_sandbox/landscape_test}"
ILANDC="${ILANDC_BIN:-D:/quinn/iLand2.1/ilandc.exe}"
HERE="$(cd "$(dirname "$0")" && pwd)"
RESULTS="${HERE}/results"

YEARS="${YEARS:-5}"
SEED="${SEED:-42}"
THREADS="${THREADS:-4 8 16 24 32}"

mode="${1:-threads}"

XML="${SANDBOX}/landscape_test.xml"
[ -f "${XML}" ] || { echo "sandbox not provisioned: run setup_sandbox.sh" >&2; exit 1; }

# Refuse an unpatched project file. The scenario XML ships nine
# `overwritten_by_csv` placeholders that the production runner fills from a CSV
# row; setup_sandbox.sh bakes them in via patch_sandbox_xml.R. Without that,
# environmentFile fails outright AND epsilon silently runs at 0 instead of 2.7 --
# the run would complete and the timings would be of the wrong workload.
if grep -qE "<(environmentFile|epsilon|fireReturnInterval)>overwritten_by_csv<" "${XML}"; then
    echo "project file still has CSV placeholders: ${XML}" >&2
    echo "  run setup_sandbox.sh -- it calls patch_sandbox_xml.R" >&2
    exit 1
fi
[ -x "${ILANDC}" ] || [ -f "${ILANDC}" ] || { echo "ilandc not found: ${ILANDC}" >&2; exit 1; }
mkdir -p "${RESULTS}"

# One run. Args: tag, thread count, then any extra key=value overrides.
run_one() {
    local tag=$1 threads=$2; shift 2
    local out="${SANDBOX}/output/${tag}"
    rm -rf "${out}"
    mkdir -p "${out}"/{log,kbdi,crownkill,nFire}

    local tmp_xml="${SANDBOX}/_run_${tag}.xml"
    cp "${SANDBOX}/landscape_test.xml" "${tmp_xml}"
    # iLand needs <output> to point at this run's directory. Forward slashes only:
    # backslashes are escape sequences to sed.
    sed -i "s|<output>.*</output>|<output>${out}</output>|" "${tmp_xml}"

    # Only the experimental variables and the per-run paths are passed here.
    # Everything else (climate, spp_param, epsilon, fri, onlysim, minDbh, the
    # grids, the snapshot) is baked into the project file by setup_sandbox.sh, so
    # there is one source of truth rather than two that can drift.
    echo "=== ${tag}: ${threads} threads, ${YEARS} years, seed ${SEED} $*"

    # Peak memory, sampled while the process is alive -- PeakWorkingSet64 is gone
    # by the time the child exits. Suppressed with NO_POLL=1 by the concurrency
    # mode, which runs ONE poller across all instances to get the node total.
    local poller=""
    if [ "${NO_POLL:-0}" != "1" ]; then
        rm -f "${RESULTS}/mem_${tag}.txt"
        powershell -NoProfile -ExecutionPolicy Bypass             -File "$(cygpath -m "${HERE}/poll_memory.ps1")"             -OutFile "$(cygpath -m "${RESULTS}/mem_${tag}.txt")" -IntervalSec 2 \
            -TraceFile "$(cygpath -m "${RESULTS}/memtrace_${tag}.csv")" &
        poller=$!
    fi

    local t0=$(date +%s)
    "${ILANDC}" "${tmp_xml}" "${YEARS}" \
        system.settings.threadCount="${threads}" \
        system.settings.randomSeed="${SEED}" \
        system.database.out="${tag}.sqlite" \
        system.logging.logFile="${out}/log/log.txt" \
        "$@" > "${out}/log/stdout.txt" 2>&1 || {
            echo "  RUN FAILED -- see ${out}/log/" >&2
            tail -5 "${out}/log/stdout.txt" >&2 || true
        }
    local t1=$(date +%s)
    [ -n "${poller}" ] && { wait "${poller}" 2>/dev/null || true; }
    echo "  wall $(( t1 - t0 ))s$( [ -f "${RESULTS}/mem_${tag}.txt" ] && awk '{printf ", peak %.1f GB", $1/1073741824}' "${RESULTS}/mem_${tag}.txt" )"

    cp "${out}/log/log.txt" "${RESULTS}/log_${tag}.txt" 2>/dev/null || true
    # The databases are DELIBERATELY KEPT, not deleted. The correctness gate --
    # every config must report identical fire-table row counts, proving the seed
    # was honoured -- can only be checked after the runs, and it has to pass
    # before any timing is worth reading. ~8 GB per config on a 1.6 TB disk.
    # parse_timers.R reports the total so you know what to clean up.
    rm -f "${tmp_xml}"
}

case "$mode" in
  threads)
    for t in ${THREADS}; do
        run_one "t${t}" "${t}"
    done
    ;;
  nooutput)
    # Pure compute scaling, with every big output block switched off. The threads
    # sweep already yields this as (runYear - outputs), but that subtraction
    # assumes output and compute do not overlap. Disabling the writers removes
    # the assumption, and answers the separate question of how many threads a
    # spinup wants -- a spinup writes on only 41 of its 300 years, so most of its
    # years look like these runs, not like the scenario runs.
    for t in ${THREADS}; do
        run_one "n${t}${TAG_SFX:-}" "${t}" \
            output.stand.enabled=false \
            output.saplingdetail.enabled=false \
            output.carbon.enabled=false \
            output.water.enabled=false
    done
    ;;
  geotiff)
    # Correctness first: identical seed, identical years, only the grid format
    # differs. If the row counts disagree the .tif inputs are not equivalent and
    # the timing is irrelevant.
    t="${GEOTIFF_THREADS:-32}"
    run_one "fmt_txt" "${t}" \
        model.world.environmentGrid=gis/env.grid.txt \
        model.world.DEM=gis/DEM_processed.txt \
        model.world.standGrid.fileName=gis/stand_grid_yr1.txt
    run_one "fmt_tif" "${t}" \
        model.world.environmentGrid=gis/env.grid.tif \
        model.world.DEM=gis/DEM_processed.tif \
        model.world.standGrid.fileName=gis/stand_grid_yr1.tif
    ;;
  memthreads)
    # Experiment A: does thread count change the MEMORY footprint? Same seed,
    # same years, same grids -- only threadCount differs. If peak RSS is flat,
    # per-step memory is set by the landscape state (the snapshot's trees plus
    # the 313 M-cell light grid), and no thread setting will fit more steps on a
    # node. 8 vs 32 because above 32 is SMT here, and the question is only
    # directional.
    # TAG_SFX keeps a differently-parameterised probe (e.g. YEARS=86) from
    # overwriting the 5-year sweep it is being compared against.
    for t in ${MEM_THREADS:-8 32}; do
        run_one "m${t}${TAG_SFX:-}" "${t}"
    done
    ;;
  concurrency)
    # Experiment B: how many concurrent instances fit in a Derecho node's 235 GB?
    # ONE poller spans all instances, because the summed peak is what the node
    # has to hold -- not the per-instance figure.
    #
    # Memory transfers to Derecho (255.5 GB here vs 256 GB there). Runtime does
    # NOT: 4 x 8 threads saturates all 32 physical cores here but is a quarter of
    # Derecho's 128, so local slowdown under concurrency is a worst case.
    N="${CONC_N:-3}"; t="${CONC_THREADS:-8}"
    mem_file="${RESULTS}/mem_conc${N}x${t}.txt"
    rm -f "${mem_file}"
    powershell -NoProfile -ExecutionPolicy Bypass \
        -File "$(cygpath -m "${HERE}/poll_memory.ps1")" \
        -OutFile "$(cygpath -m "${mem_file}")" -IntervalSec 2 &
    poller=$!
    echo "### ${N} concurrent instances, ${t} threads each"
    pids=""
    for i in $(seq 1 "${N}"); do
        NO_POLL=1 run_one "c${N}x${t}_i${i}" "${t}" &
        pids="${pids} $!"
    done
    fail=0
    for pp in ${pids}; do wait "${pp}" || fail=1; done
    wait "${poller}" 2>/dev/null || true
    echo
    awk -v n="${N}" '"'"'{ g=$1/1073741824;
        printf "### summed peak %.1f GB across %d instances = %.1f GB each\n", g, n, g/n;
        if (g > 235) printf "### OVER the 235 GB node budget by %.1f GB\n", g-235;
        else printf "### %.1f GB headroom against a 235 GB node\n", 235-g }'"'"' "${mem_file}"
    [ "${fail}" = "0" ] || echo "### at least one instance FAILED -- check logs before believing the memory figure" >&2
    ;;
  *) echo "usage: $0 [threads|nooutput|geotiff|memthreads|concurrency]" >&2; exit 1 ;;
esac

echo
echo "logs in ${RESULTS}; now run: Rscript thread-scaling-test/parse_timers.R"
