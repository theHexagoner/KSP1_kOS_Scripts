@LAZYGLOBAL OFF.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  Progress                                                                                                              //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Do we need a reference to the CPU for the Soyuz rocket?
GLOBAL linkToLvCPU IS 0.

// Keep track of the launch shroud 
GLOBAL launchShroudsAll IS LIST().
GLOBAL launchShroud IS 0.

GLOBAL decouplerModuleStageThree IS 0.			// there is a stack decoupler for dropping S3


// PID controller. We will need these to dock.
// GLOBAL rcsForePIDController IS PIDLOOP(1,0.1,0.01,0.01,1).
// GLOBAL rcsTransPIDController IS PIDLOOP(1,0.1,0.01,0.01,1).


GLOBAL FUNCTION GetProgressSpacecraft {

	// Get a reference TO the launch shroud
	IF NOT SHIP:PARTSTAGGED("SHROUDL"):EMPTY {
		launchShroudsAll:ADD(SHIP:PARTSTAGGED("SHROUDL")).
		SET launchShroud TO SHIP:PARTSTAGGED("SHROUDL")[0].
	}

	// get a reference TO the stage 3 decoupler
	IF NOT SHIP:PARTSTAGGED("S3_DECO"):EMPTY {
		SET decouplerModuleStageThree TO SHIP:PARTSTAGGED("S3_DECO")[0]:GETMODULE("ModuleDecouple").
	}

	IF NOT SHIP:PARTSTAGGED("LvCpu"):EMPTY {
		SET linkToLvCPU TO SHIP:PARTSTAGGED("LvCpu")[0]:GETMODULE("kOSProcessor"):CONNECTION.
	}
	
	RETURN validateAll().

}

LOCAL FUNCTION validateAll {

	// check TO make sure we've got all the references that are expected TO be SET for this guidance program
	// IF any of these fail, it generally means that our parts tags have not been SET properly
	
	IF launchShroudsAll:EMPTY {
		MissionLog("FAIL: Missing launch shroud").
        RETURN FALSE.	
	}

	IF decouplerModuleStageThree = 0 {
		MissionLog("FAIL: Missing S3 decoupler").
        RETURN FALSE.
	}
	
	IF SHIP:PARTSTAGGED("LvCpu"):EMPTY {
		MissionLog("FAIL: can't find lift vehicle CPU.").
        RETURN FALSE.
	}
	
	RETURN TRUE.
}




