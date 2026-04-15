set -e # terminate if non-zero exit
set -u  # terminate if variable unset
set -o pipefail  # terminate if any command in pipeline fails

# Arguments
xml=$1
start_rep=$2
end_rep=$3

# Set variables
path="/glade/work/qasena/iLand2.0/iland-model/build/ilandc/ilandc"
output_path="/glade/derecho/scratch/qasena/output_auto/CPCRW_hist_spinup"
xml_path="/glade/work/qasena/iLand_automated"
simulation_years="300"
csv_name="/glade/work/qasena/iLand_automated/iland_reps.csv"

mkdir -p "${output_path}"

# Read CSV and loop through lines
sed 1d "$csv_name" | while IFS=, read -r sp_param gcm fri epsilon dbh sp_init stand_grid env_file id
do
    for rep in $(seq "$start_rep" "$end_rep")
    do
        echo "running gcm $gcm with sp_param $sp_param rep $rep"

        scenario_dir="${output_path}/${gcm}_${sp_param}_ep${epsilon}_dbh${dbh}_${id}/rep_${rep}"
        tmp_xml="${xml_path}/${gcm}_${sp_param}_ep${epsilon}_dbh${dbh}_${id}_${rep}.xml"

        mkdir -p "${scenario_dir}/crownkill"
		mkdir -p "${scenario_dir}/nFire"
        mkdir -p "${scenario_dir}/log"

        # Create modified XML with unique output path
        cp "$xml" "$tmp_xml"
        sed -i "s|<output>.*</output>|<output>${scenario_dir}</output>|" "$tmp_xml"

        # Run iLand model
        "${path}" "$tmp_xml" "$simulation_years" \
            system.database.out=${gcm}_${sp_param}_ep${epsilon}_dbh${dbh}_${id}_${rep}.sqlite \
            system.logging.logFile=${scenario_dir}/log/log.txt \
            system.database.climate=${gcm}.sqlite \
            system.database.in=${sp_param}.sqlite \
            modules.fire.fireReturnInterval=${fri} \
			model.settings.epsilon=${epsilon} \
		    output.saplingdetail.minDbh=${dbh}
			world.standGrid.fileName=${stand_grid}
			world.environmentFile=${env_file}
			initialization.saplingFile=${sp_init}

        rm "$tmp_xml"

    done
done
