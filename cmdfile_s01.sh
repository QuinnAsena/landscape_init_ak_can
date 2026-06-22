# launch_cf -A UCIE0001 -l walltime=18:00:00 --steps-per-node 2 --ppn 128 --nthreads 80 --mem 235GB -l job_priority=economy /glade/work/qasena/landscape_init_ak_can/cmdfile_s01.sh
bash /glade/work/qasena/landscape_init_ak_can/run_iland_csv_cpxml_apptainer.sh /glade/work/qasena/landscape_init_ak_can/landscape_alaska_03/landscape_alaska_03_1950-1980spinup.xml 10 10 300
bash /glade/work/qasena/landscape_init_ak_can/run_iland_csv_cpxml_apptainer.sh /glade/work/qasena/landscape_init_ak_can/landscape_alaska_03/landscape_alaska_03_1950-1980spinup.xml 11 11 300
# bash /glade/work/qasena/landscape_init_ak_can/run_iland_csv_cpxml_apptainer.sh /glade/work/qasena/landscape_init_ak_can/landscape_alaska_03/landscape_alaska_03_1950-1980spinup.xml 12 12 300
