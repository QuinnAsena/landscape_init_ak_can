# move lip directories to each landscape

# move spp database to each landscape's database directory

# create scripts directory per landsacpe and copy javascripts there


# takes maximalist project file, and replaces: 
# <world> width, height, latitude, location xyz

# if spinup = TRUE
	# <initialization>
	#   <mode>standgrid</mode> <!-- standgrid'unit': separate initailization for each resource unit, 'single': one initialization for the full area -->
    #   <type>distribution</type><!-- distribution-->
	#   <randomFunction>max(1-x^2,0)</randomFunction> 
    #   <file></file> <!-- bare_ground.txt #tree.txt snapshot.sqlite-->
# else:
	# <initialization>
	#   <mode>snapshot</mode> <!-- standgrid'unit': separate initailization for each resource unit, 'single': one initialization for the full area -->
    #   <type>iland</type><!-- distribution-->
	#   <randomFunction>max(1-x^2,0)</randomFunction> 
    #   <file>/glade/work/qasena/iLand_automated/snapshot/spinup_300.sqlite</file> <!-- bare_ground.txt #tree.txt snapshot.sqlite-->
	#   <saplingFile>cpcrw_model_init.txt</saplingFile> <!-- cpcrw_model_init.txt sapling.txt-->



# - batchYears
# - randomSamplingList
# - <filter>2006>year</filter>
