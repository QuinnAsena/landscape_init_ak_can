# -A UCIE0001 -l
# walltime=6:00:00
# --ppn 128
# --steps-per-node 3 # number of jobs run on a single node
# --mem 235GB
# -l job_priority=economy
# --nthreads 36 #  multiplied across nodes threads 36 = 108 total threads across three steps
# Launch with /glade/work/benkirk/repos/NCAR-pbstools/bin/launch_cf -A UCIE0001 -l walltime=12:00:00 --steps-per-node 3 --ppn 40 --mem 235GB --queue casper -l job_priority=economy /glade/work/qasena/landscape_init_ak_can/cmdfile_runreplicates_csv_CASPER.sh
bash /glade/work/qasena/landscape_init_ak_can/run_iland_csv_cpxml.sh /glade/work/qasena/landscape_init_ak_can/landscape_alaska_01/landscape_alaska_01_1950-1980spinup.xml 1 1 300 casper
bash /glade/work/qasena/landscape_init_ak_can/run_iland_csv_cpxml.sh /glade/work/qasena/landscape_init_ak_can/landscape_alaska_01/landscape_alaska_01_1950-1980spinup.xml 2 2 300 casper
bash /glade/work/qasena/landscape_init_ak_can/run_iland_csv_cpxml.sh /glade/work/qasena/landscape_init_ak_can/landscape_alaska_01/landscape_alaska_01_1950-1980spinup.xml 3 3 300 casper


launch_cf -A UCIE0001 -l walltime=12:00:00 --steps-per-node 3 --ppn 36 --mem 235GB --queue casper -l job_priority=economy /glade/work/qasena/landscape_init_ak_can/cmdfile_runreplicates_csv_CASPER
launch_cf -A UCIE0001 -l walltime=12:00:00 --steps-per-node 3 --nthreads 36 --mem 235GB --queue casper -l job_priority=economy /glade/work/qasena/landscape_init_ak_can/cmdfile_runreplicates_csv_CASPER

launch_cf -A UCIE0001 -l walltime=12:00:00 --steps-per-node 3 --ppn 36 --nthreads 12 --mem 235GB --queue casper -l job_priority=economy /glade/work/qasena/landscape_init_ak_can/cmdfile_runreplicates_csv_CASPER


# Argument definitions
# --steps-per-node 3 : number of jobs run on a single node
# --ppn 36 : Divide across steps per node, max per step = 36? 128 total available cores per node on Derecho and Casper
# --mem 235GB : Total ram requested per node, do not need to divide across steps per node
# --nthreads 12 # Divide by ppn

# Math
# 3 steps-per-node * 36 ppn = 108 cpus in use
# steps_per_node*threads_per_step = 3*12 = 36 threads per step
# 36 ppn / steps-per-node = 12 (threads per step)

# Casper and Derecho capacity
# CPUs/ppn 128 max for Derecho and Casper
# RAM/mem 235GB max for Derecho and Casper