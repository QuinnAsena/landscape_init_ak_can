# /glade/work/benkirk/repos/NCAR-pbstools/bin/launch_cf -A UCIE0001 -l walltime=2:00:00 --steps-per-node 4 --mem 235GB -l --queue casper job_priority=economy /glade/work/qasena/landscape_init_ak_can/analysis-scripts/cmdfile_process_area_dom.sh
# /glade/work/benkirk/repos/NCAR-pbstools/bin/launch_cf -A UCIE0001 -l walltime=2:00:00 --nthreads 12 --ppn 36 --steps-per-node 3 --mem 235GB -l --queue casper job_priority=economy /glade/work/qasena/landscape_init_ak_can/analysis-scripts/cmdfile_process_area_dom.sh
# /glade/work/benkirk/repos/NCAR-pbstools/bin/launch_cf -A UCIE0001 -l walltime=1:00:00 --nthreads 6 --ppn 36 --steps-per-node 6 --mem 235GB -l --queue casper job_priority=economy /glade/work/qasena/landscape_init_ak_can/analysis-scripts/cmdfile_process_area_dom.sh
# launch_cf -A UCIE0001 -l walltime=1:00:00 --nthreads 14 --ppn 128 --steps-per-node 9 --mem 235GB -l job_priority=economy /glade/work/qasena/landscape_init_ak_can/analysis-scripts/cmdfile_process_area_dom.sh

# Post-spinup area_dom processing for the landscapes whose spinups have finished.
# Rewritten 2026-08-25: every previous line targeted landscape 03 with the old
# treatment format (_yr_1_iLand2.1 suffix, no fri), both of which changed when the
# runner naming contract became ${gcm}_dbh${dbh}_onlysim${onlysim}_fri${fri}.
#
# Treatment below is derived from spin-up-launch/iland_spinups.csv through that
# contract: gcm=NorEsm2-MMssp126, dbh=2.5, onlysim=false, fri=120, id empty.
# process_area_dom.R reads the stand and saplingdetail tables, both of which the
# spinup XMLs keep enabled, so it needs no changes for spinup output.
#
# 2 landscapes x 9 replicates = 18 lines. At --steps-per-node 9 that is 2 full
# nodes. The historical notes above used 9 steps/node against 86-year scenario
# databases; these are 300-year spinups at ~25 GB, so check qhist
# resources_used.mem on the first job in case the larger databases change the
# picture. 9 steps/node is the setting that has previously run smoothly here.
#
# Current invocation (one line):
# launch_cf -A UCIE0001 -l walltime=2:00:00 --nthreads 14 --ppn 128 --steps-per-node 9 --mem 235GB -l job_priority=economy /glade/work/qasena/landscape_init_ak_can/analysis-scripts/cmdfile_process_area_dom.sh
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_01_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 1
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_01_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 2
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_01_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 3
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_01_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 4
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_01_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 5
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_01_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 6
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_01_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 7
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_01_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 8
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_01_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 9
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_02_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 1
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_02_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 2
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_02_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 3
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_02_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 4
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_02_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 5
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_02_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 6
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_02_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 7
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_02_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 8
module purge; module load conda; conda activate my-r-4.4; Rscript /glade/work/qasena/landscape_init_ak_can/analysis-scripts/process_area_dom.R "landscape_alaska_02_1950-1980spinup" "NorEsm2-MMssp126_dbh2.5_onlysimfalse_fri120" 9
