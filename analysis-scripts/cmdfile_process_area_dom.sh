# /glade/work/benkirk/repos/NCAR-pbstools/bin/launch_cf -A UCIE0001 -l walltime=2:00:00 --steps-per-node 4 --mem 235GB -l --queue casper job_priority=economy /glade/work/qasena/landscape_init_ak_can/analysis-scripts/cmdfile_process_area_dom.sh
# /glade/work/benkirk/repos/NCAR-pbstools/bin/launch_cf -A UCIE0001 -l walltime=2:00:00 --nthreads 12 --ppn 36 --steps-per-node 3 --mem 235GB -l --queue casper job_priority=economy /glade/work/qasena/landscape_init_ak_can/analysis-scripts/cmdfile_process_area_dom.sh
# /glade/work/benkirk/repos/NCAR-pbstools/bin/launch_cf -A UCIE0001 -l walltime=1:00:00 --nthreads 6 --ppn 36 --steps-per-node 6 --mem 235GB -l --queue casper job_priority=economy /glade/work/qasena/landscape_init_ak_can/analysis-scripts/cmdfile_process_area_dom.sh
# launch_cf -A UCIE0001 -l walltime=1:00:00 --nthreads 14 --ppn 128 --steps-per-node 9 --mem 235GB -l job_priority=economy /glade/work/qasena/landscape_init_ak_can/analysis-scripts/cmdfile_process_area_dom.sh
# Post-spinup area_dom processing for the landscapes whose spinups have finished.
#
# Treatment is derived from spin-up-launch/iland_spinups.csv through the runner
# naming contract ${gcm}_dbh${dbh}_onlysim${onlysim}_fri${fri}:
#   gcm=NorEsm2-MMssp126, dbh=2.5, onlysim=false, fri=120, id empty.
# process_area_dom.R reads the stand and saplingdetail tables, both of which the
# spinup XMLs keep enabled, so it needs no changes for spinup output.
#
# SIZING, measured from job 7240498 -- the --steps-per-node 9 run on line 4:
#   node[0]  79.23 GB over 8 real steps =  9.90 GB/step
#   node[1]  90.05 GB over 9 real steps = 10.01 GB/step
#   elapsed 13-17 min against a 2 h walltime
#
# CAVEAT: job 7240498 processed landscapes 01 and 02. The lines below are 03 and 04,
# so those figures are INFERRED to transfer, not measured on them. Basis: the spinup
# jobs put 03 close to 01 (149-154 vs 146-154 GB/node) and 04 close to 02 (132-139
# vs 133-138), so processing load should be comparable. Confirm from qhist on the
# first 03/04 job -- at 18 x ~10 GB there is ~55 GB of slack against 235 GB.
#
# That run used only ~45 of 128 cores and ~90 of 235 GB per node. Each step forks
# plan(multicore, workers = min(nrow(chunks), 10)), and the spinup writes stand and
# saplingdetail only for year >= 260 -- 41 years, span 10, so 5 chunks and therefore
# 5 workers per step. Nine steps was a third of the node on both axes.
#
# All 18 lines now fit on ONE node:
#   memory  18 x ~10 GB = ~180 GB of 235 (~205 GB at the 14% spread between nodes)
#   cores   18 x 5 workers = 90 of 128
#   --nthreads 7 gives 18 x 7 = 126 of 128, comfortably above the 5 forks per step
# One node for ~20 min beats two for ~15 min on node-hours, and a 1-node request
# backfills sooner. Walltime cut 2 h -> 1 h: even 3x the observed time fits.
#
# DO NOT put blank lines in this file. launch_cf skips # comments but COUNTS blank
# lines as steps -- one blank at line 5 on 2026-08-25 displaced the tail of the file
# and landscape_02 rep 9 never ran. Pre-flight check before submitting:
#   grep -c '^[[:space:]]*$' <file>   # must be 0
#   grep -vc '^#' <file>              # must equal the expected step count
#
# NOT transferable to scenario processing. Scenario runs write all 86 years, so
# chunks go 5 -> 9 and workers per step 5 -> 9 (cores then allow only ~14 steps per
# node), and each step holds more data so per-step memory will exceed 10 GB by an
# unmeasured amount. Re-measure on the first scenario processing job.
#
# Current invocation (one line):
# launch_cf -A UCIE0001 -l walltime=1:00:00 --nthreads 7 --ppn 128 --steps-per-node 18 --mem 235GB -l job_priority=economy /glade/work/qasena/landscape_init_ak_can/analysis-scripts/cmdfile_process_area_dom.sh
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_05_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 1
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_05_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 2
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_05_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 3
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_05_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 4
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_05_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 5
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_05_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 6
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_05_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 7
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_05_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 8
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_05_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 9
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_06_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 1
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_06_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 2
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_06_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 3
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_06_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 4
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_06_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 5
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_06_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 6
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_06_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 7
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_06_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 8
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_06_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 9
