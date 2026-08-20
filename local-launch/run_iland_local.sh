# Local (Cuddles) launch commands for run_iland_csv_cpxml_local.sh.
#
# This is a notebook, not a script to run top to bottom -- that would launch every
# block in sequence. Run the SETUP lines, then copy the block you want.
#
# Paths are absolute, so a block behaves the same whether it is pasted into a
# shell sitting in the repo root, in this directory, or anywhere else. Previously
# these were relative and only worked from the root, which broke when the launch
# files moved into local-launch/. Override ILAND_REPO if the checkout moves.
#
# Every block names its own CSV via ILAND_SCENARIO_CSV, so no block depends on
# whatever the runner happens to default to, and switching tracks needs no edits.
# The pairing matters and is not enforced -- a mismatch runs happily with the
# wrong fri/gcm set, and the output directory name will not reveal it:
#   iland_scenarios_onlyfire.csv          <-> *_2015-2100scenario_onlyfire.xml
#   iland_scenarios_onlyfire_historic.csv <-> *_1950-2015historic_onlyfire.xml
# The runner echoes the CSV it resolved on startup -- worth a glance.
#
# The per-landscape blocks are separate on purpose: each is launched in its own
# terminal so landscapes run concurrently. Three at a time saturates this machine
# (~98% CPU), so do not add a fourth.

# ---------------------------------- SETUP ----------------------------------- #

root="${ILAND_REPO:-Z:/personal_storage/quinn_storage/landscape_init_ak_can}"
runner="${root}/local-launch/run_iland_csv_cpxml_local.sh"

# Arguments: <xml> <start_rep> <end_rep> <simulation_years>
#
# Output defaults to landscape_alaska_NN/output, beside the project file, so
# ILANDC_OUTPUT_ROOT no longer has to be set on every call. The binary defaults to
# D:/quinn/iLand2.1/ilandc; set ILANDC_BIN to test another build, e.g.
#   ILANDC_BIN="D:/quinn/iLand2.0/ilandc" bash "${runner}" ...


# ------------------------ scenario runs, 2015-2100 -------------------------- #

# ten reps of a single landscape
for n in 01; do
    ILAND_SCENARIO_CSV=iland_scenarios_onlyfire.csv \
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_2015-2100scenario_onlyfire.xml" 1 10 86
done

# ten reps of each landscape, one landscape after another in a single terminal
for n in 01 02 03; do
    ILAND_SCENARIO_CSV=iland_scenarios_onlyfire.csv \
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_2015-2100scenario_onlyfire.xml" 1 10 86
done


#### one rep per landscape -- run each block in its own terminal

for n in 01; do
    ILAND_SCENARIO_CSV=iland_scenarios_onlyfire.csv \
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_2015-2100scenario_onlyfire.xml" 1 1 86
done

for n in 02; do
    ILAND_SCENARIO_CSV=iland_scenarios_onlyfire.csv \
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_2015-2100scenario_onlyfire.xml" 1 1 86
done

for n in 03; do
    ILAND_SCENARIO_CSV=iland_scenarios_onlyfire.csv \
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_2015-2100scenario_onlyfire.xml" 1 1 86
done


###################################
##### historic only fire runs #####
###################################
# 66 simulation years, started from the spinup snapshot.

for n in 04; do
    ILAND_SCENARIO_CSV=iland_scenarios_onlyfire_historic.csv \
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_1950-2015historic_onlyfire.xml" 1 1 66
done

for n in 05; do
    ILAND_SCENARIO_CSV=iland_scenarios_onlyfire_historic.csv \
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_1950-2015historic_onlyfire.xml" 1 1 66
done

for n in 06; do
    ILAND_SCENARIO_CSV=iland_scenarios_onlyfire_historic.csv \
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_1950-2015historic_onlyfire.xml" 1 1 66
done

###################################
#####      spinup  test       #####
###################################
# NOTE the CSV: iland_spinups.csv lives in spin-up-launch/, not here, so it must
# be given as a FULL PATH. A bare filename is resolved against this directory and
# would not be found.
#
# 300 years is the real spinup and takes many hours locally. For a wiring test use
# 10 years, NOT 2: onYearEnd fires for years 1..N and the spinup workflow writes
# KBDI only when year % 10 == 0, so a 2-year run produces no grid at all and
# proves nothing. A 10-year run produces kbdi_10.txt, which confirms
# saveWorkflow_spinup.js was found, parsed and fired. Only a full 300-year run
# writes snapshot/spinup_300.sqlite.

for n in 01; do
    ILAND_SCENARIO_CSV="${root}/spin-up-launch/iland_spinups.csv" \
    bash "${runner}" \
        "${root}/landscape_alaska_${n}/landscape_alaska_${n}_1950-1980spinup.xml" 1 1 300
done
