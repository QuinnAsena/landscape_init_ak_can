# Local (Cuddles) launch commands for run_iland_csv_cpxml_local.sh.
#
# This is a notebook, not a script to run top to bottom -- that would launch every
# block in sequence. Run the SETUP lines, then copy the block you want.
#
# Paths are absolute, so a block behaves the same whether it is pasted into a
# shell sitting in the repo root, in this directory, or anywhere else. Previously
# these were relative and only worked from the root, which broke when the launch
# files moved into onlyfire_local/. Override ILAND_REPO if the checkout moves.
#
# WHICH CSV RUNS IS SET IN THE RUNNER, NOT HERE. run_iland_csv_cpxml_local.sh
# hard-codes csv_name and nothing checks it against the XML passed in. Before a
# scenario block that line must read iland_scenarios_onlyfire.csv; before a
# historic block, iland_scenarios_onlyfire_historic.csv. Getting it wrong still
# runs, but with the wrong fri/gcm set, and the output directory name will not
# make the mistake obvious.
#
# The per-landscape blocks are separate on purpose: each is launched in its own
# terminal so landscapes run concurrently. Three at a time saturates this machine
# (~98% CPU), so do not add a fourth.

# ---------------------------------- SETUP ----------------------------------- #

root="${ILAND_REPO:-Z:/personal_storage/quinn_storage/landscape_init_ak_can}"
runner="${root}/onlyfire_local/run_iland_csv_cpxml_local.sh"

# Arguments: <xml> <start_rep> <end_rep> <simulation_years>
#
# Output defaults to landscape_alaska_NN/output, beside the project file, so
# ILANDC_OUTPUT_ROOT no longer has to be set on every call. The binary defaults to
# D:/quinn/iLand2.1/ilandc; set ILANDC_BIN to test another build, e.g.
#   ILANDC_BIN="D:/quinn/iLand2.0/ilandc" bash "${runner}" ...


# ------------------------ scenario runs, 2015-2100 -------------------------- #
# Runner must be pointing at iland_scenarios_onlyfire.csv

# ten reps of a single landscape
for n in 01; do
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_2015-2100scenario_onlyfire.xml" 1 10 86
done

# ten reps of each landscape, one landscape after another in a single terminal
for n in 01 02 03; do
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_2015-2100scenario_onlyfire.xml" 1 10 86
done


#### one rep per landscape -- run each block in its own terminal

for n in 01; do
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_2015-2100scenario_onlyfire.xml" 1 1 86
done

for n in 02; do
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_2015-2100scenario_onlyfire.xml" 1 1 86
done

for n in 03; do
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_2015-2100scenario_onlyfire.xml" 1 1 86
done


###################################
##### historic only fire runs #####
###################################
# Runner must be pointing at iland_scenarios_onlyfire_historic.csv
# 66 simulation years, started from the spinup snapshot.

for n in 04; do
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_1950-2015historic_onlyfire.xml" 1 1 66
done

for n in 05; do
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_1950-2015historic_onlyfire.xml" 1 1 66
done

for n in 06; do
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_1950-2015historic_onlyfire.xml" 1 1 66
done
