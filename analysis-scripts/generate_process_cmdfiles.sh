#!/bin/bash
# Generate Derecho cmdfiles for the per-replicate processing scripts.
#
#   bash analysis-scripts/generate_process_cmdfiles.sh --kind scenario --landscapes "01 02"
#   bash analysis-scripts/generate_process_cmdfiles.sh --kind spinup   --landscapes "05 06"
#   bash analysis-scripts/generate_process_cmdfiles.sh --kind scenario --analysis seed_dens --landscapes "01"
#
# WHY THIS EXISTS. Chain A's scenario output alone needs 312 processing lines and all
# six landscapes need 936, which is not hand-writable. The hand-maintained
# cmdfile_process_*.sh files stay exactly as they are -- this writes new files into
# generated/ and never touches them.
#
# TREATMENT NAMES ARE READ FROM THE SCENARIO CSVs, NOT DUPLICATED HERE. The runner
# builds each output directory as
#     ${gcm}_dbh${dbh}_onlysim${onlysim}_fri${fri}${id:+_${id}}
# from a CSV row, so this script parses the same rows through the same rule. That makes
# drift structurally impossible: there is one definition of a treatment name, in the
# CSVs. Hand-written cmdfiles are how `_yr_1_iLand2.1` survived for months after the
# runner stopped emitting it.
#
# REP COUNTS ARE READ FROM scenario-launch/generate_cmdfiles.sh for the same reason --
# if the run matrix changes reps, processing follows automatically.
#
# NO BLANK LINES ARE EMITTED. launch_cf skips `#` comments but COUNTS blank lines as
# steps: one blank in a hand-edited cmdfile on 2026-08-25 displaced the tail of the file
# and a replicate never ran. The pre-flight at the end re-checks this every time.
#
# OUT OF SCOPE: process_fire_regime.R, which takes (landscape, treatment) and aggregates
# across replicates rather than taking a rep argument. Different shape; run per landscape
# by hand.
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
DIR="/glade/work/qasena/landscape_init_ak_can"        # path as seen on Derecho
PRE="module purge; module load conda; conda activate my-r-4.4; Rscript"

kind=""
analysis="area_dom"
landscapes=""
while [ $# -gt 0 ]; do
    case "$1" in
        --kind)       kind="$2"; shift 2 ;;
        --analysis)   analysis="$2"; shift 2 ;;
        --landscapes) landscapes="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done

case "$kind" in
    spinup|scenario) ;;
    *) echo "usage: $0 --kind <spinup|scenario> [--analysis area_dom|basal_area|seed_dens] --landscapes \"01 02\"" >&2; exit 1 ;;
esac
case "$analysis" in
    area_dom|basal_area|seed_dens) ;;
    *) echo "--analysis must be area_dom, basal_area or seed_dens (all take landscape/treatment/rep)." >&2
       echo "  process_fire_regime.R is per-treatment, not per-rep -- not handled here." >&2; exit 1 ;;
esac
[ -n "${landscapes}" ] || { echo "--landscapes is required, e.g. --landscapes \"01 02\"" >&2; exit 1; }

rscript="${repo_dir}/analysis-scripts/process_${analysis}.R"
[ -f "${rscript}" ] || { echo "no such analysis script: ${rscript}" >&2; exit 1; }

out_dir="${repo_dir}/analysis-scripts/generated"
mkdir -p "${out_dir}"

# Build "treatment<TAB>reps" pairs for the requested kind. One place decides both.
gen_dir="${repo_dir}/scenario-launch"
tmp_treat=$(mktemp)
trap 'rm -f "${tmp_treat}"' EXIT

if [ "$kind" = "scenario" ]; then
    # reps depend on onlysim, and must match the round that was actually run
    reps_false=$(grep -oE "^REPS_FALSE=[0-9]+" "${gen_dir}/generate_cmdfiles.sh" | cut -d= -f2)
    reps_true=$(grep -oE "^REPS_TRUE=[0-9]+"  "${gen_dir}/generate_cmdfiles.sh" | cut -d= -f2)
    [ -n "${reps_false}" ] && [ -n "${reps_true}" ] || {
        echo "could not read REPS_FALSE/REPS_TRUE from ${gen_dir}/generate_cmdfiles.sh" >&2
        echo "  they define how many replicates exist per treatment; refusing to guess." >&2
        exit 1; }
    period="2015-2100scenario"

    csvs=("${gen_dir}"/iland_scenarios_ssp*_sim*_fri*.csv)
    (( ${#csvs[@]} )) || { echo "no scenario CSVs found in ${gen_dir}" >&2; exit 1; }
    for csv in "${csvs[@]}"; do
        # columns: sp_param,gcm,fri,epsilon,dbh,stand_grid,env_file,id,snapshot_file,onlysim
        tail -n +2 "$csv" | while IFS=, read -r sp_param gcm fri epsilon dbh stand_grid env_file id snapshot_file onlysim; do
            [ -n "${gcm}" ] || continue
            onlysim=$(echo "${onlysim}" | tr -d ' \r')
            suffix=""
            [ -n "${id}" ] && suffix="_${id}"
            if [ "${onlysim}" = "false" ]; then reps="${reps_false}"; else reps="${reps_true}"; fi
            printf '%s_dbh%s_onlysim%s_fri%s%s\t%s\n' "${gcm}" "${dbh}" "${onlysim}" "${fri}" "${suffix}" "${reps}"
        done
    done | sort -u > "${tmp_treat}"
else
    reps_spin=9        # one cmdfile per landscape is 9 replicates; see spin-up-launch/
    period="1950-1980spinup"
    csv="${repo_dir}/spin-up-launch/iland_spinups.csv"
    [ -f "${csv}" ] || { echo "no spinup CSV at ${csv}" >&2; exit 1; }
    tail -n +2 "$csv" | while IFS=, read -r sp_param gcm fri epsilon dbh stand_grid env_file id snapshot_file onlysim; do
        [ -n "${gcm}" ] || continue
        onlysim=$(echo "${onlysim}" | tr -d ' \r')
        suffix=""
        [ -n "${id}" ] && suffix="_${id}"
        printf '%s_dbh%s_onlysim%s_fri%s%s\t%s\n' "${gcm}" "${dbh}" "${onlysim}" "${fri}" "${suffix}" "${reps_spin}"
    done | sort -u > "${tmp_treat}"
fi

n_treat=$(wc -l < "${tmp_treat}")
(( n_treat > 0 )) || { echo "no treatments derived -- check the CSVs" >&2; exit 1; }

# Sizing guidance differs by kind because the number of year-chunks does, and that sets
# how many workers each step forks: process_*.R uses plan(multicore, workers =
# min(nrow(chunks), 10)) over seq(min_yr, max_yr, by = span=10).
if [ "$kind" = "spinup" ]; then
    size_note=(
      "# SIZING. Spinup output is written only for year >= 260, so 41 years at span 10 is"
      "# 5 chunks = 5 workers per step. Measured on job 7240498 (landscapes 01/02):"
      "# ~10 GB/step, 13-17 min elapsed. 18 steps/node is proven -- 180 GB of 235, and"
      "# 18 x 5 = 90 of 128 cores. Set --nthreads at or above 5."
    )
    spn=18
else
    size_note=(
      "# SIZING. Scenario output has NO year condition on stand/saplingdetail, so all 86"
      "# years are written: 9 chunks = 9 workers per step, against the spinup's 5. Cores"
      "# therefore cap this near 14 steps/node (14 x 9 = 126 of 128)."
      "#"
      "# PER-STEP MEMORY IS UNMEASURED for scenario processing. The spinup measured ~10"
      "# GB/step over 41 output years; 86 years is roughly double the table volume, so"
      "# 10-20 GB/step is the plausible range -- inferred, not observed. At 12 steps/node"
      "# that is 144-240 GB against 235, i.e. the top of the range does not fit."
      "# Start at 12, read qhist resources_used.mem on the first job, and drop to 8-10 if"
      "# per-step lands near 20 GB. Do NOT carry the spinup's 18 across."
    )
    spn=12
fi

total=0
for n in ${landscapes}; do
    landscape="landscape_alaska_${n}_${period}"
    f="${out_dir}/cmdfile_${analysis}_${kind}_${n}.sh"

    {
        echo "# GENERATED by analysis-scripts/generate_process_cmdfiles.sh -- do not hand-edit."
        echo "# Regenerate with:"
        echo "#   bash analysis-scripts/generate_process_cmdfiles.sh --kind ${kind} --analysis ${analysis} --landscapes \"${n}\""
        echo "#"
        echo "# ${analysis} processing for ${landscape}."
        echo "# Treatments are derived from the run CSVs through the runner's naming contract,"
        echo "# so they cannot drift from the directories the runs actually produced."
        echo "#"
        printf '%s\n' "${size_note[@]}"
        echo "#"
        echo "# Suggested invocation (one line):"
        echo "# launch_cf -A UCIE0001 -l walltime=2:00:00 --nthreads 9 --ppn 128 --steps-per-node ${spn} --mem 235GB -l job_priority=economy ${DIR}/analysis-scripts/generated/$(basename "$f")"
        echo "#"
        echo "# NEVER add a blank line below: launch_cf counts blanks as steps and would"
        echo "# silently displace the last command."
        while IFS=$'\t' read -r treatment reps; do
            for rep in $(seq 1 "${reps}"); do
                echo "${PRE} ${DIR}/analysis-scripts/process_${analysis}.R \"${landscape}\" \"${treatment}\" ${rep}"
            done
        done < "${tmp_treat}"
    } > "$f"

    # Pre-flight, every time, on the file just written.
    blanks=$(grep -c '^[[:space:]]*$' "$f" || true)
    cmds=$(grep -vc '^#' "$f" || true)
    if (( blanks != 0 )); then
        echo "  ERROR: ${blanks} blank line(s) in $(basename "$f") -- launch_cf would eat a step" >&2
        exit 1
    fi
    nodes=$(( (cmds + spn - 1) / spn ))
    printf "  %-34s %4d lines, 0 blanks -> %2d node(s) at --steps-per-node %d" \
           "$(basename "$f")" "$cmds" "$nodes" "$spn"
    if (( cmds % spn )); then
        printf "  (last node runs %d)\n" $(( cmds % spn ))
    else
        printf "  (exact)\n"
    fi
    total=$(( total + cmds ))
done

echo "  ${n_treat} treatment(s) x reps, ${total} processing line(s) total in ${out_dir}"
echo "  Spot-check before submitting: the treatment strings must match directories that"
echo "  exist under /glade/derecho/scratch/qasena/output_ak_can/<landscape>/"
