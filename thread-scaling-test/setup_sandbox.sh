#!/bin/bash
# Provision an isolated iLand project for the thread-scaling benchmark.
#   bash thread-scaling-test/setup_sandbox.sh
#
# Why isolated: the benchmark rewrites the same output path once per thread
# count. Pointing that at landscape_alaska_01/output/ risks colliding with real
# results, and a self-contained copy means a re-run months from now is not
# affected by the landscape directory having moved on.
#
# Why on D:: Z: is a network drive. The benchmark writes ~0.8 GB per simulated
# year, and doing that across the network would make iLand's `outputs` timer
# network-bound -- fatal, because output cost is the main quantity being measured.
# The project inputs (climate, gis) are read from Z: but that is constant across
# configs and so cannot bias the comparison.
#
# ~14 GB, almost all of it the climate database and the snapshot, which is why
# this lives outside the repo and is rebuilt by this script rather than committed.
set -euo pipefail

REPO="${ILAND_REPO:-Z:/personal_storage/quinn_storage/landscape_init_ak_can}"
SRC="${REPO}/landscape_alaska_01"
SANDBOX="${ILAND_SANDBOX:-D:/quinn/iland_sandbox/landscape_test}"

# The snapshot is a TIMING ARTEFACT, not a scientific input. It is one arbitrary
# local replicate at KBDIref 0.029 -- NOT the replicate process_fire_regime.R
# will select from the Derecho spinups. Copied under a name that cannot be
# mistaken for the real thing, because a plausible-looking spinup_300.sqlite
# lying around is exactly the trap the 2026-08-21 archive was created to close.
SNAP_SRC="${SRC}/output/NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120/rep_1/spinup_300.sqlite"
SNAP_NAME="spinup_300_TIMING_ONLY.sqlite"

GCM="NorEsm2-MMssp126"   # one climate database is enough for a timing test

# The scenario XML ships nine `overwritten_by_csv` placeholders that the production
# runner fills from a CSV row. They are baked into the sandbox XML instead, from
# this CSV, so the benchmark project file is self-contained and still derived
# rather than hand-edited. The spinups CSV is the default because its gcm matches
# the one climate database copied below, and the snapshot came from exactly that
# configuration. Point PARAM_CSV at a scenario CSV only if you also copy that
# GCM's database.
PARAM_CSV="${PARAM_CSV:-${REPO}/spin-up-launch/iland_spinups.csv}"

echo "repo:    ${REPO}"
echo "sandbox: ${SANDBOX}"

for f in "${SRC}/landscape_alaska_01_2015-2100scenario.xml" "${SNAP_SRC}" "${PARAM_CSV}" \
         "${SRC}/databases/${GCM}.sqlite" "${SRC}/databases/spp_param.sqlite"; do
    [ -e "$f" ] || { echo "missing required input: $f" >&2; exit 1; }
done

mkdir -p "${SANDBOX}"/{gis,init,databases,lip,scripts,snapshot,output}

# Project file. iLand resolves relative paths against the project home, so the
# sandbox becomes the home and no path rewriting is needed -- but the CSV-driven
# placeholders must be filled, or iLand fails on
# "Environment: input file does not exist (.../overwritten_by_csv)" and, more
# quietly, runs with epsilon=0 instead of the intended value.
cp "${SRC}/landscape_alaska_01_2015-2100scenario.xml" "${SANDBOX}/landscape_test.xml"

# Grid inputs: both .txt and .tif, because Part 3 swaps between them.
cp "${SRC}"/gis/env.grid.txt "${SRC}"/gis/env.grid.tif \
   "${SRC}"/gis/DEM_processed.txt "${SRC}"/gis/DEM_processed.tif \
   "${SRC}"/gis/stand_grid_yr1.txt "${SRC}"/gis/stand_grid_yr1.tif \
   "${SRC}"/gis/env.file_link_yr_1.txt "${SANDBOX}/gis/"
# DEM_processed.txt needs its .prj alongside; harmless if absent.
cp "${SRC}"/gis/*.prj "${SANDBOX}/gis/" 2>/dev/null || true

cp "${SRC}/init/landscape_model_init.txt" "${SANDBOX}/init/"
cp "${SRC}/scripts/saveWorkflow_scenario.js" "${SANDBOX}/scripts/"
cp -r "${SRC}/lip/." "${SANDBOX}/lip/"

echo "copying databases (~1.8 GB) ..."
cp "${SRC}/databases/${GCM}.sqlite" "${SRC}/databases/spp_param.sqlite" "${SANDBOX}/databases/"

echo "copying snapshot (~10 GB) ..."
cp "${SNAP_SRC}" "${SANDBOX}/snapshot/${SNAP_NAME}"

echo "filling CSV-driven placeholders in the project file ..."
Rscript "$(cd "$(dirname "$0")" && pwd)/patch_sandbox_xml.R" \
    "${SANDBOX}/landscape_test.xml" \
    "${PARAM_CSV}" \
    "snapshot/${SNAP_NAME%.sqlite}"

cat > "${SANDBOX}/README_SANDBOX.txt" <<TXT
Thread-scaling benchmark sandbox -- DISPOSABLE, NOT SCIENTIFIC OUTPUT
=====================================================================
Provisioned by thread-scaling-test/setup_sandbox.sh from
${SRC}

snapshot/${SNAP_NAME}
  A TIMING ARTEFACT. One arbitrary local replicate run at KBDIref 0.029. It is
  NOT the snapshot landscape_alaska_01 should use. The real one is selected by
  analysis-scripts/process_fire_regime.R (best_rep) from the Derecho spinup
  outputs and downloaded manually. Do not copy this anywhere named
  spinup_300.sqlite.

Everything here can be deleted and rebuilt. Nothing in it feeds any result.
TXT

printf "\ndone. sandbox size:\n"
du -sh "${SANDBOX}" 2>/dev/null | sed 's/^/  /'
