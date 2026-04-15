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
sed 1d "$csv_name" | while IFS=, read -r fecund gcm fri epsilon dbh id
do
    for rep in $(seq "$start_rep" "$end_rep")
    do
        echo "running gcm $gcm with fecund $fecund rep $rep"

        scenario_dir="${output_path}/${gcm}_${fecund}_ep${epsilon}_dbh${dbh}_${id}/rep_${rep}"
        tmp_xml="${xml_path}/${gcm}_${fecund}_ep${epsilon}_dbh${dbh}_${id}_${rep}.xml"

        mkdir -p "${scenario_dir}/crownkill"
		mkdir -p "${scenario_dir}/nFire"
        mkdir -p "${scenario_dir}/log"

        # Create modified XML with unique output path
        cp "$xml" "$tmp_xml"
        sed -i "s|<output>.*</output>|<output>${scenario_dir}</output>|" "$tmp_xml"

        # Run iLand model
        "${path}" "$tmp_xml" "$simulation_years" \
            system.database.out=${gcm}_${fecund}_ep${epsilon}_dbh${dbh}_${id}_${rep}.sqlite \
            system.database.climate=${gcm}.sqlite \
            system.database.in=${fecund}.sqlite \
            system.logging.logFile=${scenario_dir}/log/log_${gcm}_${fecund}_ep${epsilon}_dbh${dbh}_${id}_${rep}.txt \
            modules.fire.fireReturnInterval=${fri} \
			model.settings.epsilon=${epsilon} \
		    output.saplingdetail.minDbh=${dbh}

        rm "$tmp_xml"

    done
done
