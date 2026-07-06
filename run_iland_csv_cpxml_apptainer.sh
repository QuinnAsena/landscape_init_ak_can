set -e          # terminate if non-zero exit
set -u          # terminate if variable unset
set -o pipefail # terminate if any command in pipeline fails

# Arguments
xml=$1
start_rep=$2
end_rep=$3
simulation_years=$4

# Set variables
xml_path=$(dirname "$xml")
landscape_name=$(basename "$xml" .xml)
output_path="$(realpath -m "${ILANDC_OUTPUT_ROOT:-/glade/derecho/scratch/qasena/output_ak_can/${landscape_name}}")"
script_dir=$(cd "$(dirname "$0")" && pwd)
csv_name="${script_dir}/iland_scenarios.csv"

mkdir -p "${output_path}"

module load apptainer

# Clean up temp XML on exit. Note: the while loop runs in a subshell (due to
# the pipe), so tmp_xml set inside the loop is not visible here. The rm inside
# the loop handles normal cleanup; this trap covers any exit before the loop.
trap 'rm -f "${tmp_xml:-}"' EXIT

# Read CSV and loop through lines
sed '1d' "$csv_name" | while IFS=, read -r sp_param gcm fri epsilon dbh stand_grid env_file id snapshot_file onlysim
do
    for rep in $(seq "$start_rep" "$end_rep")
    do
        echo "running gcm $gcm, id $id, rep $rep, $stand_grid, $env_file, $onlysim"

        scenario_dir="${output_path}/${gcm}_dbh${dbh}_onlysim${onlysim}_${id}/rep_${rep}"
        tmp_xml="${xml_path}/${gcm}_dbh${dbh}_onlysim${onlysim}_${id}_${rep}.xml"

        mkdir -p "${scenario_dir}/crownkill"
        mkdir -p "${scenario_dir}/nFire"
        mkdir -p "${scenario_dir}/log"

        # Create modified XML with unique output path
        cp "$xml" "$tmp_xml"
        sed -i "s|<output>.*</output>|<output>${scenario_dir}</output>|" "$tmp_xml"

        # Conditionally pass snapshot file (scenario runs only; blank for spinup)
        extra_args=()
        [ -n "${snapshot_file}" ] && extra_args+=("model.initialization.file=${snapshot_file}.sqlite")

        # Run iLand model via Apptainer container
        apptainer exec --bind /glade/derecho/scratch /glade/work/qasena/iLandc_container/ilandv2p1.sif ilandc \
            "$tmp_xml" "$simulation_years" \
            system.database.out=${gcm}_dbh${dbh}_onlysim${onlysim}_${id}_${rep}.sqlite \
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
