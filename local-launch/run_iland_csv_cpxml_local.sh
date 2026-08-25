set -e          # terminate if non-zero exit
set -u          # terminate if variable unset
set -o pipefail # terminate if any command in pipeline fails

# LOCAL-ONLY runner (Cuddles). The Derecho/Casper variants live at the repo root:
# run_iland_csv_cpxml_apptainer.sh for the HPC. Nothing here knows about glade
# paths, launch_cf or the `system` argument -- keep it that way, and if a change
# needs to apply to the HPC too, make it there as well (the two runners are
# deliberately separate, not a shared file).

# Arguments
xml=$1
start_rep=$2
end_rep=$3
simulation_years=$4

# Set variables
# ILANDC_BIN overrides the binary (e.g. to test against iLand 2.0);
# ILANDC_OUTPUT_ROOT overrides where output goes.
path="${ILANDC_BIN:-D:/quinn/iLand2.1/ilandc}"
xml_path=$(dirname "$xml")
landscape_name=$(basename "$xml" .xml)
# Default output sits beside the project file, i.e. landscape_alaska_NN/output,
# which is where these runs have always been directed by hand.
output_path="$(realpath -m "${ILANDC_OUTPUT_ROOT:-${xml_path}/output}")"
# On Windows (Git Bash / MSYS2) realpath converts Z:/... to /z/... but iLand
# is a native Windows binary and cannot resolve POSIX-style drive paths.
# cygpath -m gives a Windows path with forward slashes (Z:/...) — iLand can
# read it, and forward slashes are safe in sed replacement strings unlike the
# backslashes produced by cygpath -w (\l, \p etc. have special sed meanings).
if command -v cygpath &>/dev/null; then
  output_path="$(cygpath -m "${output_path}")"
fi
script_dir=$(cd "$(dirname "$0")" && pwd)

# Which scenario CSV to run. Set ILAND_SCENARIO_CSV to switch tracks instead of
# editing this line -- accepts either a bare filename in this directory or a full
# path. The CSV must match the XML passed in:
#   iland_scenarios_onlyfire.csv          <-> *_2015-2100scenario_onlyfire.xml
#   iland_scenarios_onlyfire_historic.csv <-> *_1950-2015historic_onlyfire.xml
# A mismatch still runs, just with the wrong fri/gcm set, and the output
# directory name will not make it obvious -- so run_iland_local.sh sets this
# explicitly in every block rather than relying on the default below.
csv_name="${ILAND_SCENARIO_CSV:-iland_scenarios_onlyfire_historic.csv}"

# Resolve a bare filename against this directory; leave a full path alone.
[ -f "${csv_name}" ] || csv_name="${script_dir}/${csv_name}"
if [ ! -f "${csv_name}" ]; then
    echo "scenario CSV not found: ${csv_name}" >&2
    echo "  set ILAND_SCENARIO_CSV to a filename in ${script_dir} or a full path" >&2
    exit 1
fi
echo "scenario CSV: ${csv_name}"

# iLand thread count. The project files carry <threadCount>-1</threadCount>, i.e. every
# available core -- 64 logical on this machine, and 256 on a Derecho node. Measured
# 2026-08-24: a replicate stops getting faster at 8 threads, because ~50% of a run is
# seed dispersal, which is parallel over SPECIES (4 in these landscapes) and caps at
# ~3.24x. Leaving it at -1 is why three concurrent local instances pegged the CPU at
# 98% -- 192 threads on 64 cores -- without running any faster.
ILAND_THREADS="${ILAND_THREADS:-16}"

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
        # made the new runs overwrite the old ones. id is optional; the local CSVs
        # set it ("onlyfire", "onlyfire_historic") to keep these runs separate from
        # the HPC output, which leaves it blank.
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
            system.settings.threadCount=${ILAND_THREADS} \
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
