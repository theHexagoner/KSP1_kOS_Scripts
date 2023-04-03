@LAZYGLOBAL OFF.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// Soyuz Rocket                                                                                                       ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Keep a reference to the CPU in the payload:
GLOBAL linkToPayloadCPU IS 0.

// Keep track of our engines
GLOBAL enginesStageOneAll IS LIST().			// This will include Blok A,B,V,G,D at launch       
GLOBAL enginesStageOneBoosters IS LIST().    	// This will include Blok B,V,G,D at launch
GLOBAL engineStageTwo IS 0.        				// This IS Blok A
GLOBAL engineStageThree IS 0.          			// This IS Blok I

// keep track of the fuel available TO Stage 2
GLOBAL tanksStageTwo IS LIST().					// apparently also not used?

// keep track of stage decouplers
GLOBAL decouplerModulesStageOneAll IS LIST().	// there are four radial decouplers for dropping S1 boosters
GLOBAL decouplerModuleStageTwo IS 0.			// there IS a stack decoupler for dropping S2
GLOBAL decouplerModuleStageThree IS 0.			// there IS a stack decoupler for dropping S3

// in case of bad trouble
GLOBAL selfDestructModule IS 0.

GLOBAL FUNCTION GetSoyuzRocket {

	// get the CPU in the payload
	IF NOT SHIP:PARTSTAGGED("payCpu"):EMPTY AND 
       SHIP:PARTSTAGGED("payCpu")[0]:HASMODULE("kOSProcessor") {
		SET linkToPayloadCPU TO SHIP:PARTSTAGGED("payCpu")[0]:GETMODULE("kOSProcessor"):CONNECTION.
	}

	// Find the probe core that is controlling this rocket
	IF NOT SHIP:PARTSTAGGED("LvCpu"):EMPTY AND
	   SHIP:PARTSTAGGED("LvCpu")[0]:HASMODULE("TacSelfDestruct") {
		SET selfDestructModule TO SHIP:PARTSTAGGED("LvCpu")[0]:GETMODULE("TacSelfDestruct").	
	}

    // Find all engines on the vehicle that are in stage one.
	IF NOT SHIP:PARTSTAGGEDPATTERN("BLOK_A"):EMPTY { 
		enginesStageOneAll:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_A")[0]).
		SET engineStageTwo TO SHIP:PARTSTAGGEDPATTERN("BLOK_A")[0]. // also track Blok A as Stage 2
	}
	
	IF NOT SHIP:PARTSTAGGEDPATTERN("BLOK_B"):EMPTY {
		enginesStageOneAll:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_B")[0]).
		enginesStageOneBoosters:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_B")[0]).
	}

	IF NOT SHIP:PARTSTAGGEDPATTERN("BLOK_V"):EMPTY {
		enginesStageOneAll:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_V")[0]).
		enginesStageOneBoosters:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_V")[0]).
	}

	IF NOT SHIP:PARTSTAGGEDPATTERN("BLOK_G"):EMPTY {
		enginesStageOneAll:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_G")[0]).
		enginesStageOneBoosters:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_G")[0]).
	}

	IF NOT SHIP:PARTSTAGGEDPATTERN("BLOK_D"):EMPTY {
		enginesStageOneAll:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_D")[0]).
		enginesStageOneBoosters:ADD(SHIP:PARTSTAGGEDPATTERN("BLOK_D")[0]).
	}

	// get a reference TO the decoupler modules on stage 1:
	for f in SHIP:PARTSTAGGED("S1_DECO") {
		decouplerModulesStageOneAll:ADD(f:GETMODULE("ModuleAnchoredDecoupler")).
	}

	// get a reference TO the decoupler module on stage 2:    
	for f in SHIP:PARTSTAGGED("S2_DECO") {
		SET decouplerModuleStageTwo TO f:GETMODULE("ModuleDecouple").	
	}
	
	// get a reference TO all the Stage 2 tanks:
	IF NOT SHIP:PARTSTAGGED("S2_TANK"):EMPTY {
		SET tanksStageTwo TO SHIP:PARTSTAGGED("S2_TANK").	
	}
	
	// Track Blok I as Stage 3
	IF NOT SHIP:PARTSTAGGEDPATTERN("BLOK_I"):EMPTY {
		SET engineStageThree TO SHIP:PARTSTAGGEDPATTERN("BLOK_I")[0].
	}
	
	// get a reference TO the stage 3 decoupler
	IF NOT SHIP:PARTSTAGGED("S3_DECO"):EMPTY {
		SET decouplerModuleStageThree TO SHIP:PARTSTAGGED("S3_DECO")[0]:GETMODULE("ModuleDecouple").
	}

	RETURN validateAll().
}

LOCAL FUNCTION validateAll {

	// check TO make sure we've got all the references that are expected TO be SET for this guidance program
	// IF any of these fail, it generally means that our parts tags have not been SET properly
    
    IF enginesStageOneAll:LENGTH <> 5 {
		MissionLog("FAIL: Missing one or more S1 engines").
        RETURN FALSE.
    } 

	IF enginesStageOneBoosters:LENGTH <> 4 {
		MissionLog("FAIL: Missing S1 booster engines").
        RETURN FALSE.
	}

	IF decouplerModulesStageOneAll:LENGTH <> 4 {
		MissionLog("FAIL: Missing S1 decoupler").
        RETURN FALSE.
	}

	IF engineStageTwo = 0 {
		MissionLog("FAIL: Missing S2 engine").
        RETURN FALSE.
	}

	IF decouplerModuleStageTwo = 0 {
		MissionLog("FAIL: Missing S2 decoupler").
        RETURN FALSE.
	}

	IF tanksStageTwo:EMPTY {
		MissionLog("FAIL: Missing S2 tankage").
        RETURN FALSE.
	}

	IF engineStageThree = 0 {
		MissionLog("FAIL: Missing S3 engine").
        RETURN FALSE.
	}

	IF decouplerModuleStageThree = 0 {
		MissionLog("FAIL: Missing S3 decoupler").
        RETURN FALSE.
	}

	// get the CPU in the payload
	IF SHIP:PARTSTAGGED("payCpu"):EMPTY {
		MissionLog("FAIL: cannot find payload CPU").
		RETURN FALSE.
	}

	// Find the probe core that is controlling this rocket
	IF SHIP:PARTSTAGGED("LvCpu"):EMPTY OR 
	   NOT SHIP:PARTSTAGGED("LvCpu")[0]:HASMODULE("TacSelfDestruct") {
		MissionLog("FAIL: RSO did not find ordinance").
		RETURN FALSE.
	}

	RETURN TRUE.
}





