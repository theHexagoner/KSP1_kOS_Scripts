@LAZYGLOBAL OFF.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// Soyuz Rocket                                                                                                       ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Keep track of our engines
global enginesStageOneAll is LIST().			// This will include Blok A,B,V,G,D at launch       
global enginesStageOneBoosters is LIST().    	// This will include Blok B,V,G,D at launch
global engineStageTwo is 0.        				// This is Blok A
global engineStageThree is 0.          			// This is Blok I

// keep track of the fuel available to Stage 2
global tanksStageTwo is LIST().					// apparently also not used?

// keep track of stage decouplers
global decouplerModulesStageOneAll is LIST().	// there are four radial decouplers for dropping S1 boosters
global decouplerModuleStageTwo is 0.			// there is a stack decoupler for dropping S2

// these are currently not used for anything, but eventually we will add a routine to separate and deorbit S3
global decouplerModuleStageThree is 0.			// there is a stack decoupler for dropping S3
global sepratronsStageThree is LIST().			// there are some separator engines on S3 to get it away

// find the launch clamps:
local launchClamps is LIST().
local launchClampsKosTag is "LAUNCHPAD".
local launchClampModuleNames is LEXICON(). 
launchClampModuleNames:ADD("Stock", "LaunchClamp").
launchClampModuleNames:ADD("ReStock", "ModuleRestockLaunchClamp").

// use these to release the launch clamps
global launchClampModules is LIST().	
global launchClampEventName is "Release Clamp".

// use these to sound the alarm:
global warningSirenModule is 0.
global warningSirenModuleName is "PebkacWarningSiren".
global warningEventName is "Sound the Alarm".


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// Progress Spacecraft                                                                                                ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Keep track of the launch shroud 
global launchShroudsAll is LIST().
global launchShroud is 0.

// PID controller. Coefficients have been determined empirically.
// This would be used to during Coast mode to supply RCS bursts to keep us from losing too much altitude while in the atmosphere
// TODO: figure out if/how this actually does anything useful
global rcsForePIDController  is PIDLOOP(0.001, 0.001, 0.000, 0.0, 1.0).

global function GetPartsAndModules {

    // Find all engines on the vehicle that are in stage one.
	if NOT SHIP:PARTSTAGGEDPATTERN("BLOK_A"):EMPTY { 
		enginesStageOneAll:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_A")[0]).
		set engineStageTwo to SHIP:PARTSTAGGEDPATTERN("BLOK_A")[0]. // also track Blok A as Stage 2
	}
	
	if NOT SHIP:PARTSTAGGEDPATTERN("BLOK_B"):EMPTY {
		enginesStageOneAll:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_B")[0]).
		enginesStageOneBoosters:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_B")[0]).
	}

	if NOT SHIP:PARTSTAGGEDPATTERN("BLOK_V"):EMPTY {
		enginesStageOneAll:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_V")[0]).
		enginesStageOneBoosters:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_V")[0]).
	}

	if NOT SHIP:PARTSTAGGEDPATTERN("BLOK_G"):EMPTY {
		enginesStageOneAll:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_G")[0]).
		enginesStageOneBoosters:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_G")[0]).
	}

	if NOT SHIP:PARTSTAGGEDPATTERN("BLOK_D"):EMPTY {
		enginesStageOneAll:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_D")[0]).
		enginesStageOneBoosters:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_D")[0]).
	}

	// get a reference to the decoupler modules on stage 1:
	for f in SHIP:PARTSTAGGED("S1_DECO") {
		decouplerModulesStageOneAll:ADD(f:GETMODULE("ModuleAnchoredDecoupler")).
	}

	// get a reference to the decoupler module on stage 2:    
	for f in SHIP:PARTSTAGGED("S2_DECO") {
		set decouplerModuleStageTwo to f:GETMODULE("ModuleDecouple").	
	}
	
	// get a reference to all the Stage 2 tanks:
	if NOT SHIP:PARTSTAGGED("S2_TANK"):EMPTY {
		set tanksStageTwo to SHIP:PARTSTAGGED("S2_TANK").	
	}
	
	// Track Blok I as Stage 3
	if NOT SHIP:PARTSTAGGEDPATTERN("BLOK_I"):EMPTY {
		set engineStageThree to SHIP:PARTSTAGGEDPATTERN("BLOK_I")[0].
	}
	
	// get a reference to the stage 3 decoupler
	if NOT SHIP:PARTSTAGGED("S3_DECO"):EMPTY {
		set decouplerModuleStageThree to SHIP:PARTSTAGGED("S3_DECO")[0]:GETMODULE("ModuleDecouple").
	}

	// Get a reference to the launch shroud
	if NOT SHIP:PARTSTAGGED("SHROUDL"):EMPTY {
		launchShroudsAll:ADD(SHIP:PARTSTAGGED("SHROUDL")).
		SET launchShroud to SHIP:PARTSTAGGED("SHROUDL")[0].
	}

	// Launch clamps and associated modules
	if NOT SHIP:PARTSTAGGED(launchClampsKosTag):EMPTY {
		set launchClamps to SHIP:PARTSTAGGED(launchClampsKosTag).
		for p in launchClamps {
			// check each entry in the lexicon
			if p:HASMODULE(launchClampModuleNames["Stock"]) 
				launchClampModules:ADD(p:GETMODULE(launchClampModuleNames["Stock"])).
			
			if p:HASMODULE(launchClampModuleNames["ReStock"]) 
				launchClampModules:ADD(p:GETMODULE(launchClampModuleNames["ReStock"])).
				
			if p:HASMODULE(warningSirenModuleName)
				set warningSirenModule to p:GETMODULE(warningSirenModuleName).
		}
	}

	// Get a reference to the launch shroud
	if NOT SHIP:PARTSTAGGED("SHROUDL"):EMPTY {
		launchShroudsAll:ADD(SHIP:PARTSTAGGED("SHROUDL")).
		SET launchShroud to SHIP:PARTSTAGGED("SHROUDL")[0].
	}

	return validateAll().

}

local function validateAll {

	// check to make sure we've got all the references that are expected to be set for this guidance program
	// if any of these fail, it generally means that our parts tags have not been set properly
    
    if enginesStageOneAll:LENGTH <> 5 {
		MissionLog("FAIL: Missing one or more S1 engines").
        return FALSE.
    } 

	if enginesStageOneBoosters:LENGTH <> 4 {
		MissionLog("FAIL: Missing S1 booster engines").
        return FALSE.
	}

	if decouplerModulesStageOneAll:LENGTH <> 4 {
		MissionLog("FAIL: Missing S1 decoupler").
        return FALSE.
	}

	if engineStageTwo = 0 {
		MissionLog("FAIL: Missing S2 engine").
        return FALSE.
	}

	if decouplerModuleStageTwo = 0 {
		MissionLog("FAIL: Missing S2 decoupler").
        return FALSE.
	}

	if tanksStageTwo:EMPTY {
		MissionLog("FAIL: Missing S2 tankage").
        return FALSE.
	}

	if engineStageThree = 0 {
		MissionLog("FAIL: Missing S3 engine").
        return FALSE.
	}

	if decouplerModuleStageThree = 0 {
		MissionLog("FAIL: Missing S3 decoupler").
        return FALSE.
	}
	
	// THIS CHECK is SPECIFIC to PROGRESS:
	if launchShroudsAll:EMPTY {
		MissionLog("FAIL: Missing launch shroud").
        return FALSE.	
	}

	if launchClampModules:EMPTY {
		MissionLog("FAIL: Missing launch clamps").
        return FALSE.	
	}

	if launchClampModules:LENGTH = 1 AND
	   warningSirenModule = 0 {
		MissionLog("FAIL: Missing the klaxon").
	}

	return TRUE.
}





