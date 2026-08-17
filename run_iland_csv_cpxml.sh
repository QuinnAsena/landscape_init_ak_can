set -e          # terminate if non-zero exit
set -u          # terminate if variable unset
set -o pipefail # terminate if any command in pipeline fails

# Arguments
xml=$1
start_rep=$2
end_rep=$3
simulation_years=$4
system=${5:-derecho}   # derecho (default) or casper

# Set variables
# Override ILANDC_BIN and ILANDC_OUTPUT_ROOT for local testing; defaults are HPC paths.
case "$system" in
  casper)
    default_bin="/glade/work/qasena/iLand2.0-casper/iland-model/build/ilandc/ilandc" ;;
  *)
    default_bin="/glade/work/qasena/iLand2.0/iland-model/build/ilandc/ilandc" ;;
esac
path="${ILANDC_BIN:-${default_bin}}"
xml_path=$(dirname "$xml")
landscape_name=$(basename "$xml" .xml)
output_path="$(realpath -m "${ILANDC_OUTPUT_ROOT:-/glade/derecho/scratch/qasena/output_ak_can/${landscape_name}}")"
# On Windows (Git Bash / MSYS2) realpath converts Z:/... to /z/... but iLand
# is a native Windows binary and cannot resolve POSIX-style drive paths.
# cygpath -m gives a Windows path with forward slashes (Z:/...) — iLand can
# read it, and forward slashes are safe in sed replacement strings unlike the
# backslashes produced by cygpath -w (\l, \p etc. have special sed meanings).
if command -v cygpath &>/dev/null; then
  output_path="$(cygpath -m "${output_path}")"
fi
script_dir=$(cd "$(dirname "$0")" && pwd)
csv_name="${script_dir}/iland_scenarios_onlyfire.csv"

mkdir -p "${output_path}"

# Clean up temp XML on exit. Note: the while loop runs in a subshell (due to
# the pipe), so tmp_xml set inside the loop is not visible here. The rm inside
# the loop handles normal cleanup; this trap covers any exit before the loop.
trap 'rm -f "${tmp_xml:-}"' EXIT

# Read CSV and loop through lines
sed '1d' "$csv_name" | while IFS=, read -r sp_param gcm fri epsilon dbh stand_grid env_file id snapshot_file onlysim
do
    for rep in $(seq "$start_rep" "$end_rep")
    do
        echo "running gcm $gcm, fri $fri, id $id, rep $rep, $stand_grid, $env_file, $onlysim"

        # Single source of truth for the scenario name -- out_db and
        # system.database.out below must agree or the resume guard never fires.
        # fri is part of the name because changing it in the CSV without renaming
        # made the new runs overwrite the old ones. id is optional: it is blank in
        # the Derecho CSVs and set (e.g. "onlyfire") in the local ones.
        scenario_id="${gcm}_dbh${dbh}_onlysim${onlysim}_fri${fri}${id:+_${id}}"

        scenario_dir="${output_path}/${scenario_id}/rep_${rep}"
        tmp_xml="${xml_path}/${scenario_id}_${rep}.xml"
        out_db="${scenario_dir}/${scenario_id}_${rep}.sqlite"

        # Skip replicates whose output database already exists, so this script
        # can be re-run (e.g. after splitting landscapes across parallel bash
        # sessions, or resuming after a crash) without redoing finished reps.
        # Note: this only checks that the file exists, not that the run
        # completed successfully -- a crashed run that got as far as creating
        # the database will also be skipped. Delete the partial .sqlite (and
        # its scenario_dir) to force a rerun of that replicate.
        if [ -f "${out_db}" ]; then
            echo "Skipping gcm $gcm, fri $fri, id $id, rep $rep (output already exists: ${out_db})"
            continue
        fi

        mkdir -p "${scenario_dir}/crownkill"
        mkdir -p "${scenario_dir}/nFire"
        mkdir -p "${scenario_dir}/kbdi"
        mkdir -p "${scenario_dir}/log"

        # Create modified XML with unique output path
        cp "$xml" "$tmp_xml"
        sed -i "s|<output>.*</output>|<output>${scenario_dir}</output>|" "$tmp_xml"

        # Conditionally pass snapshot file (scenario runs only; blank for spinup)
        extra_args=()
        [ -n "${snapshot_file}" ] && extra_args+=("model.initialization.file=${snapshot_file}.sqlite")

        # Run iLand model
        "${path}" "$tmp_xml" "$simulation_years" \
            system.database.out=${scenario_id}_${rep}.sqlite \
            system.logging.logFile=${scenario_dir}/log/log.txt \
            system.database.climate=${gcm}.sqlite \
            system.database.in=${sp_param}.sqlite \
            modules.fire.fireReturnInterval=${fri} \
            modules.fire.onlySimulation=${onlysim} \
            model.settings.epsilon=${epsilon} \
            output.saplingdetail.minDbh=${dbh} \
            model.world.standGrid.fileName=${stand_grid}.txt \
            model.world.environmentFile=${env_file}.txt \
            "${extra_args[@]}"

        rm "$tmp_xml"

    done
done
