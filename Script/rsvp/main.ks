@LAZYGLOBAL OFF.

SET CONFIG:IPU TO 2000.0.

{

	LOCAL rsvp IS LEXICON(
		"goto", goto@
	).

	LOCAL hill_climb IS Import("rsvp/hill_climb").
	hill_climb:Fill_RSVP(rsvp).
	
	LOCAL lambert IS Import("rsvp/lambert").
	lambert:Fill_RSVP(rsvp).

	LOCAL rsvp_maneuver IS Import("rsvp/maneuver").
	rsvp_maneuver:Fill_RSVP(rsvp).	

	LOCAL rsvp_orbit IS Import("rsvp/orbit").
	rsvp_orbit:Fill_RSVP(rsvp).

	LOCAL refine IS Import("rsvp/refine").
	refine:Fill_RSVP(rsvp).

	LOCAL search IS Import("rsvp/search").
	search:Fill_RSVP(rsvp).

	LOCAL rsvp_transfer IS Import("rsvp/transfer").
	rsvp_transfer:Fill_RSVP(rsvp).

	LOCAL validate IS Import("rsvp/validate").
	validate:Fill_RSVP(rsvp).

	LOCAL FUNCTION Goto {
		PARAMETER destination, 
				 options IS LEXICON().
	
		// Thoroughly check supplied parameters, options and game state for
		// correctness. If any problems are found, print validation details
		// to the console then exit early.
		LOCAL maybe IS rsvp:validate_parameters(destination, options).
	
		IF NOT maybe:success {
			print maybe.
			return maybe.
		}
	
		PRINT "Params OK".
	
		// Find the lowest deltav cost transfer using the specified settings.
		LOCAL settings IS maybe:settings.
		LOCAL tuple IS rsvp:find_launch_window(destination, settings).
		
		PRINT "Found window-ish".
		
		LOCAL craft_transfer IS tuple:transfer.
		LOCAL result IS tuple:result.
	
		// If no node creation has been requested return predicted transfer details,
		// otherwise choose betwen the 4 combinations of possible transfer types.
		IF settings:create_maneuver_nodes <> "none" {
			// Both "origin_type" and "destination_type" are either the string
			// "vessel" or "body", so can be used to construct the function
			// names for transfer, for example "vessel_to_vessel" or "body_to_body".
			LOCAL key IS settings:origin_type + "_to_" + settings:destination_type.
			
			PRINT "Key: " + key.
			
			SET result TO rsvp[key](destination, settings, craft_transfer, result).
	
			IF NOT result:success {
				// Print details to the console
				IF settings:verbose {
					print result.
				}
	
				// In the case of failure delete any manuever nodes created.
				IF settings:cleanup_maneuver_nodes {
					FOR mnv IN allnodes {
						REMOVE mnv.
					}
				}
			}
		}
	
		return result.
	}

	Export(rsvp).
}


// for reference, here is how RSVP does it:

// Add delegate to the global "rsvp" lexicon.
//LOCAL FUNCTION export {
//    parameter key, value.
//
//    rsvp:add(key, value).
//}

// Add functions from all other scripts into lexicon. User can use compiled
// versions of the source, trading off less storage space vs harder to debug
// error messages.
//LOCAL FUNCTION import {
//    LOCAL source_root is scriptpath():parent.
//	
//	print "source_root: " + source_root.
//
//    for filename in source_files {
//	
//		print "filename: " + filename.
//	
//        LOCAL source_path is source_root:combine(filename).
//
//		print "source_path: " + source_path.
//
//        runoncepath(source_path, export@).
//    }
//}

// Compiles source files and copies them to a new location. This is useful to
// save space on processor hard disks that have limited capacity.
// The trade-off is that error messages are less descriptive.
//LOCAL FUNCTION compile_to {
//    parameter destination.
//
//    LOCAL source_root is scriptpath():parent.
//    LOCAL destination_root is path(destination).
//
//    // Check that path exists and is a directory.
//    IF not exists(destination_root) {
//        print destination_root + " does not exist".
//        return.
//    }
//    IF open(destination_root):isfile {
//        print destination_root + " is a file. Should be a directory".
//        return.
//    }
//
//    for filename in source_files {
//        LOCAL source_path is source_root:combine(filename + ".ks").
//        LOCAL destination_path is destination_root:combine(filename + ".ksm").
//
//        print "Compiling " + source_path.
//        compile source_path to destination_path.
//    }
//
//    print "Succesfully compiled " + source_files:length + " files to " + destination_root.
//}