# To run iLand2.1 run_iland_csv_cpxml locally
ILANDC_BIN="D:/quinn/iLand2.1/ilandc" \
ILANDC_OUTPUT_ROOT="landscape_alaska_01/output" \
bash run_iland_csv_cpxml.sh \
    landscape_alaska_01/landscape_alaska_01_2015-2100scenario_onlyfire.xml 1 10 86



# To run iLand2.0 run_iland_csv_cpxml locally
ILANDC_BIN="D:/quinn/iLand2.0/ilandc" \
ILANDC_OUTPUT_ROOT="landscape_alaska_01/output" \
bash run_iland_csv_cpxml.sh \
    landscape_alaska_01/landscape_alaska_01_1950-1980spinup_test.xml 1 1 5


# Run iLand2.1 as loop

for n in 01 02 03; do
    ILANDC_BIN="D:/quinn/iLand2.1/ilandc" \
    ILANDC_OUTPUT_ROOT="landscape_alaska_${n}/output" \
    bash run_iland_csv_cpxml.sh \
        landscape_alaska_${n}/landscape_alaska_${n}_2015-2100scenario_onlyfire.xml 1 10 86
done
