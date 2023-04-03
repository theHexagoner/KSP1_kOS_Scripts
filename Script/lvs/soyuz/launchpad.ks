@LAZYGLOBAL OFF.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Soyuz Rocket                                                                                                           //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// find the launch clamps:
LOCAL launchClamps IS LIST().
LOCAL launchClampsKosTag IS "LAUNCHPAD".
LOCAL launchClampModuleNames IS LEXICON(). 
launchClampModuleNames:ADD("Stock", "LaunchClamp").
launchClampModuleNames:ADD("ReStock", "ModuleRestockLaunchClamp").

// use these TO release the launch clamps
GLOBAL launchClampModules IS LIST().	
GLOBAL launchClampEventName IS "Release Clamp".

// use these TO sound the alarm:
GLOBAL warningSirenModule IS 0.
GLOBAL warningSirenModuleName IS "PebkacWarningSiren".
GLOBAL warningEventName IS "Sound the Alarm".


GLOBAL FUNCTION GetSoyuzLaunchpad {

	// Launch clamps and associated modules
	IF NOT SHIP:PARTSTAGGED(launchClampsKosTag):EMPTY {
		SET launchClamps TO SHIP:PARTSTAGGED(launchClampsKosTag).
		for p in launchClamps {
			// check each entry in the lexicon
			IF p:HASMODULE(launchClampModuleNames["Stock"]) 
				launchClampModules:ADD(p:GETMODULE(launchClampModuleNames["Stock"])).
			
			IF p:HASMODULE(launchClampModuleNames["ReStock"]) 
				launchClampModules:ADD(p:GETMODULE(launchClampModuleNames["ReStock"])).
				
			IF p:HASMODULE(warningSirenModuleName)
				SET warningSirenModule TO p:GETMODULE(warningSirenModuleName).
		}
	}

	RETURN validateAll().
}

LOCAL FUNCTION validateAll {

	// check TO make sure we've got all the references that are expected TO be SET for this guidance program
	// IF any of these fail, it generally means that our parts tags have not been SET properly
  
	IF launchClampModules:EMPTY {
		missionLog("FAIL: Missing launch clamps").
        RETURN FALSE.	
	}

	IF launchClampModules:LENGTH = 1 AND
	   warningSirenModule = 0 {
			missionLog("FAIL: Missing the klaxon").
			RETURN FALSE.
	} 
	
	RETURN TRUE.
}





