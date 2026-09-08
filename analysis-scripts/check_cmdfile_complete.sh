#!/bin/bash
# Report which model runs a cmdfile should have produced, and which are missing.
#
#   bash analysis-scripts/check_cmdfile_complete.sh scenario-launch/cmdfile_chA_05.sh
#   bash analysis-scripts/check_cmdfile_complete.sh scenario-launch/cmdfile_chB_01.sh --list
#
# WHY. One cmdfile line is (xml, start_rep, end_rep, years, csv), and the runner loops
# EVERY row of that CSV inside the line -- so a 16-line batch mixing ssp and fri values
# expands to 48 output directories that are tedious to check by eye.
#
# Nothing is hardcoded: the expected set is derived from the cmdfile and the CSVs it
# names, through the same naming contract the runner uses
#     ${gcm}_dbh${dbh}_onlysim${onlysim}_fri${fri}${id:+_${id}}
# so this cannot drift from what the runs actually wrote.
#
# COMPLETION TEST is the `.complete` sentinel, which run_iland_csv_cpxml_apptainer.sh
# touches only after ilandc exits 0. A rep directory that exists without it means the
# run started and did not finish -- exactly the case a frozen or killed job leaves.
#
# Run this ON DERECHO, where the scratch tree is visible. With --dry it prints the
# expected paths without checking, which is useful from a machine that cannot see them.
set -euo pipefail

cmdfile="${1:-}"
mode="${2:-check}"
[ -n "${cmdfile}" ] || { echo "usage: $0 <cmdfile> [--dry|--list]" >&2; exit 1; }
[ -f "${cmdfile}" ] || { echo "no such cmdfile: ${cmdfile}" >&2; exit 1; }

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
OUT="${ILANDC_OUTPUT_ROOT:-/glade/derecho/scratch/qasena/output_ak_can}"

expected=0; ok=0; miss=0; partial=0
missing_list=""

while read -r _ _ xml start_rep end_rep _years csv rest; do
    [ -n "${xml:-}" ] || continue
    case "$xml" in *.xml) ;; *) continue ;; esac
    landscape=$(basename "$xml" .xml)

    # the CSV path in the cmdfile is a Derecho path; fall back to the repo copy so this
    # also runs locally with --dry
    csv_local="$csv"
    [ -f "$csv_local" ] || csv_local="${repo_dir}/scenario-launch/$(basename "$csv")"
    [ -f "$csv_local" ] || csv_local="${repo_dir}/spin-up-launch/$(basename "$csv")"
    [ -f "$csv_local" ] || { echo "  cannot find CSV: $(basename "$csv")" >&2; continue; }

    for rep in $(seq "$start_rep" "$end_rep"); do
        while IFS=, read -r _sp gcm fri _eps dbh _sg _ef id _snap onlysim; do
            gcm=$(printf '%s' "${gcm:-}" | tr -d ' \r')
            [ -n "$gcm" ] || continue
            onlysim=$(printf '%s' "${onlysim:-}" | tr -d ' \r')
            id=$(printf '%s' "${id:-}" | tr -d ' \r')
            sfx=""; [ -n "$id" ] && sfx="_${id}"
            sid="${gcm}_dbh${dbh}_onlysim${onlysim}_fri${fri}${sfx}"
            d="${OUT}/${landscape}/${sid}/rep_${rep}"
            expected=$(( expected + 1 ))

            if [ "$mode" = "--dry" ]; then
                echo "  ${sid}/rep_${rep}"
            elif [ -f "${d}/.complete" ]; then
                ok=$(( ok + 1 ))
                [ "$mode" = "--list" ] && echo "  OK      ${sid}/rep_${rep}"
            elif [ -d "${d}" ]; then
                # started but never finished -- the interesting case
                partial=$(( partial + 1 ))
                sz=$(du -sh "${d}" 2>/dev/null | cut -f1 || echo "?")
                echo "  PARTIAL ${sid}/rep_${rep}   (${sz} on disk, no .complete)"
            else
                miss=$(( miss + 1 ))
                echo "  MISSING ${sid}/rep_${rep}"
                missing_list="${missing_list}${sid}/rep_${rep}"$'\n'
            fi
        done < <(tail -n +2 "$csv_local")
    done
done < <(grep -v '^#' "${cmdfile}")

echo
if [ "$mode" = "--dry" ]; then
    printf '  %d expected model runs from %s\n' "$expected" "$(basename "$cmdfile")"
else
    printf '  %s: %d expected, %d complete, %d partial, %d missing\n' \
           "$(basename "$cmdfile")" "$expected" "$ok" "$partial" "$miss"
    if (( partial > 0 )); then
        echo "  PARTIAL directories are the ones to worry about: the runner clears a"
        echo "  scenario_dir before rerunning, so a partial can be resubmitted safely,"
        echo "  but it must NOT be treated as finished output."
    fi
fi
