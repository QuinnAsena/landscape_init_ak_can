# Launch with launch_cf -A UCIE0001 -l walltime=12:00:00 --steps-per-node 3 --ppn 36 --nthreads 12 --mem 235GB --queue casper -l job_priority=economy /glade/work/qasena/landscape_init_ak_can/cmdfile_runreplicates_csv_iland2.1.sh
bash /glade/work/qasena/landscape_init_ak_can/run_iland_csv_cpxml_apptainer.sh /glade/work/qasena/landscape_init_ak_can/landscape_alaska_01/landscape_alaska_01_1950-1980spinup.xml 1 1 300
bash /glade/work/qasena/landscape_init_ak_can/run_iland_csv_cpxml_apptainer.sh /glade/work/qasena/landscape_init_ak_can/landscape_alaska_01/landscape_alaska_01_1950-1980spinup.xml 2 2 300
bash /glade/work/qasena/landscape_init_ak_can/run_iland_csv_cpxml_apptainer.sh /glade/work/qasena/landscape_init_ak_can/landscape_alaska_01/landscape_alaska_01_1950-1980spinup.xml 3 3 300
