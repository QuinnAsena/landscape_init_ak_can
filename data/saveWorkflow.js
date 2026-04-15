/* ********************************************************************
* generic disturbances (DICE-project)
* characteristics are read from project file (section user.generic_disturbance), for example:
*  <user>
*  <generic_disturbance>
*	  <return_interval>50</return_interval>
*	  <mean_size>2</mean_size>
*	  <type>topdown</type>
*  </generic_disturbance>
*  </user>
* 
*
*
*
******************************************************************** */
 
   
function snapShot() {
    if (Globals.year == 300) {
        var outputPath = Globals.path(Globals.setting('system.path.output'));
        Globals.saveModelSnapshot(outputPath + '/spinup_300.sqlite');
    }
}

function onYearEnd()
{
	snapShot()
	}
onYearEnd(Globals.year)

function screenShot()
{
if (Globals.year % 10 == 0)
   Globals.screenshot('temp/'+'image_' + Globals.year + '.png' );
	
}
screenShot()


function start_timer() { _elapsed = Globals.msec; }
function elapsed(thingi)
{
    var elapsed=Globals.msec - _elapsed;
	_elapsed = Globals.msec;
	console.log("Time: " + thingi + ": " + elapsed + "ms");
}

// Generate variable including the "Map" used for "painting" disturbed areas
var map = undefined;
var stand_src = undefined; // stand map used for selecting polygons

// the polygon_xxx variables are used for the table of polygons (see create_dist_areas.R)
var polygon_area=undefined;
var polygon_id=undefined;
var polygon_file = undefined;

var management_id = undefined;
var realized_areas=[];
var dist_areas=[];

var planned_fires = undefined;
var planned_fire_ids = undefined;
							  
function loadData()
{
 // create map
 if (map == undefined) {
  start_timer();
  map = Factory.newMap(); // qt5 way of creating objects
  stand_src = Factory.newGrid();
  
  polygon_file = Factory.newCSVFile('');
  planned_fires = Factory.newCSVFile('');										 

  stand_src.load(Globals.path('gis/perimeters_raster.txt'));
  polygon_file.loadFile(Globals.path( 'scripts/polygon_list.txt')); //Update!
  planned_fires.loadFile(Globals.path('scripts/planned_disturbance.txt'));	//list of id and year														
   

  polygon_area = [];
  for(var i=0; i<polygon_file.rowCount;++i) {
   polygon_area.push(polygon_file.value(i, 5)); // area
  }
  management_id = 0;
  console.log('loaded file with polygon-metadata. N=' + polygon_area.length);
     elapsed('loading management data');
 }

}

function createDeterministicDisturbances()
{

	map.clearProjectArea(); // clear the map again
	console.log("Im running!");
	for (var i=0;i<planned_fires.rowCount;++i) {
		
		// the coordinates of the lower left corner of the project area
		var world_x = Globals.setting('model.world.location.x');
		var world_y = Globals.setting('model.world.location.y');
		
		// now create the polygon
		var idx=-1;
		var poly_id = planned_fires.value(i, 1); // the id
		// look for the right line in the polygon list file
		for (var j=0;j<polygon_file.rowCount; ++j)
			if (polygon_file.value(j,0) == poly_id)
				idx = j;
		if (idx==-1) {
			console.log("ERROR: polygon id " + poly_id + " not found!");
			continue; //Here we are comparing the id table  to find the right polygon_id in the polygon file.
			//continue allows it to skip missing polygons which I need to fix.  If it were return not continue it would stop the loop
			// instead of rolling past the missing observation.
		}
		var poly_area = polygon_file.value(idx, 5); // area
				// lower left corner, target coordinates
		var x= polygon_file.value(idx, 1) - world_x;
		var y= polygon_file.value(idx, 3) - world_y;

		print("polygon: " + idx + " id: " + poly_id + ", area: " + poly_area + ", target: x/y: " + x + "/" + y);
		// now copy the grid:
		var realized_area = map.copyPolygonFromRect(stand_src,
			poly_id, // the id which we want to copy
			i+1, // the id on the target map
			x, y, // to point on the target map
			polygon_file.value(idx, 1) - world_x, // minx
			polygon_file.value(idx, 3) - world_y, // miny
			polygon_file.value(idx, 2) - world_x, // maxx
			polygon_file.value(idx, 4) - world_y ); // maxy
		
		realized_areas[i+1] = realized_area;
		dist_areas[i+1] = poly_area/100; // for  planned fires this is the polygon size
	}
	map.createMapIndex(); // update the stand structure in the map
	elapsed('create stand');
	
}

function run_planned_disturbances(year)
{
	// see if we have to run a fire in the current year
	for (var i=0;i<planned_fires.rowCount;++i) {
		if (planned_fires.value(i, 0) == year) {
			var fire_id = i + 1; // on the map the first fire gets id=1, ...
			var poly_id = planned_fires.value(i, 1);
			var yearpub = (Globals.year+1719);
			console.log("starting deterministic disturbance #" + fire_id);
			print('Orig_id ' +  poly_id + 'Year: ' + yearpub);
			
			management_id = fire_id;
	
	var disturbance_type = Globals.setting('user.generic_disturbance.type');
	
	console.log('create event (' + disturbance_type + '): size(ha)=' + dist_areas[management_id] + "; realized: " + realized_areas[management_id] );


	
	// do the management on that polygon
	management.loadFromMap(map, management_id); // load all trees within that area
	elapsed('load from map');
	 var before_filter = management.count;
	 var killed = management.count;
     var before_ba = management.sum("basalarea");
	 var before_vol = management.sum("volume");	
	 var before_carbon = management.sum("(woodymass+rootmass+foliagemass)/2");	
		management.disturbanceKill(stem_to_soil_fraction=0.05, stem_to_snag_fraction=0.9,branch_to_soil_fraction=0.05,branch_to_snag_fraction=0.8,agent='fire');
		management.killSaplings(map, management_id); //  kill also all trees <4m
	
	var after_ba = management.sum("basalarea");
	var after_vol = management.sum("volume");
	var after_carbon = management.sum("(woodymass+rootmass+foliagemass)/2");

	var killed = management.count;										  
	print('killed ' + management.count + 'from ' + before_filter);
	
	
	// write a line to the log file
			   


	add_log(Globals.year + ',' + dist_areas[management_id] + ',' + realized_areas[management_id] + ',' + ',' + before_filter + ',' + killed + ',' +
	        before_ba + ','+after_ba+ ','+ before_vol + ',' + after_vol + ',' + before_carbon + ',' + after_carbon);
	
	elapsed('management')
		}
	}
}



// helper function for creating an output
var log_text='';
function add_log(new_line)
{
	if (log_text=='')
		log_text = 'year, size_ha, realized_ha, type, trees_before, trees_killed, before_ba, removed_ba, before_vol, removed_vol, before_carbon, removed_carbon';
	log_text = log_text + '\n' + new_line;
	// save to file
	var file_name = Globals.defaultDirectory('output') + "disturbances.txt";
	print(file_name);
	Globals.saveTextFile( file_name, log_text);
}										 

// main function
function manage(year)
{
///If you want to turn on the image each five years and the sqlite database.
///screenShot()
   var praefix = Globals.year;
	loadData(); // only done once
	snapShot();
	  // Fire.gridToFile('kbdi','output/kbdi/kbdi_' + praefix + '.txt');
	//createDeterministicDisturbances();
	//run_planned_disturbances(Globals.year);

  }						 
manage(Globals.year)

function afterFireProcessing() {
   var outputPath = Globals.path(Globals.setting('system.path.output'));
   var praefix = Globals.year;
   var pid = Fire.id;
   var nFire = Fire.grid('nFire');
 
   console.log("Full Hierarchical Output Path: " + outputPath);
  
   Fire.gridToFile('crownkill', outputPath + '/crownkill/crownkill_' + pid + '_' + praefix + '.txt');
   //Fire.gridToFile('basalarea', outputPath + '/basalarea/basalarea_' + pid + '_' + praefix + '.txt');
   //Fire.gridToFile('spread', outputPath + '/spread/spread_' + pid + '.txt');
   nFire.save(outputPath + '/nFire/nFire_' + pid + '.asc');
}

// *****************************   Test function below **************************************
// *****************************     
