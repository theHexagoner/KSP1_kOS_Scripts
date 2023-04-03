@LAZYGLOBAL OFF.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//	MODULAR LAUNCH PADS																									////
//	This is logic for initializing and controlling an MLP Soyuz launch experience                                       ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// PARTS AND MODULE REFERENCES

local tMinus60s is 0.
local tMinus40s is 0.
local tMinus20s is 0.
local tMinus15s is 0.
local tMinus5s is 0.
local tTimeS is 0.

local mlpStep is 0.0.
		
local launchPad is 0.
local launchPadKosTag is "LAUNCHPAD".
local launchClampModule is 0.
local launchClampModuleName is "LaunchClamp".
local launchClampEventName is "Release Clamp".
		
local warningSirenModule is 0.
local warningSirenModuleName is "PebkacWarningSiren".
local warningEventName is "Sound the Alarm".
		
local s3Umbilical is 0.
local s3UmbilicalKosTag is "S3_UMB".
local s3UmbilicalAnimModuleIndex is 6.
local s3UmbilicalAnimModule is 0.
		
local s3Vent is 0.
local s3VentKosTag is "S3_Vent".
local s3VentModule is 0.
		
local s2Umbilical is 0.
local s2UmbilicalKosTag is "S2_UMB".
local s2UmbilicalAnimModuleIndex is 3.
local s2UmbilicalAnimModule is 0.
		
local s2Vent is 0.
local s2VentKosTag is "S2_Vent".
local s2VentModule is 0.
		
local s1Umbilicals is LIST().
local s1UmbilicalsKosTag is "S1_UMB".
local s1UmbilicalsAnimModuleIndex is 2.
local s1UmbilicalsAnimModules is LIST().
local s1UmbilicalsEventName is "Retract Clamp Arm".
		
local s1Vents is LIST().
local s1VentsKosTag is "S1_Vent".
local s1VentsModules is LIST().
		
local ventModuleName is "MakeSteam".
local ventEventName is "Hide Vapor".
local umbilicalAnimModuleName is "ModuleAnimateGenericExtra".
local umbilicalEventName is "Retract Arm".


// initialize all the parts and modules:
global function initializeMLP {
	PARAMETER launchTimeS. // seconds from epoch

	if tMinus60s = 0 {
		
		set tMinus60s to launchTimeS - 60.
		set tMinus40s to launchTimeS - 40.
		set tMinus20s to launchTimeS - 20.
		set tMinus15s to launchTimeS - 15.
		set tMinus5s to launchTimeS - 5.
		set tTimeS to launchTimeS.

		// Launch pad and associated modules
		if NOT SHIP:PARTSTAGGED(launchPadKosTag):EMPTY {
			set launchPad to SHIP:PARTSTAGGED(launchPadKosTag)[0].
		
			if launchPad:HASMODULE(warningSirenModuleName) {
				set warningSirenModule to launchPad:GETMODULE(warningSirenModuleName).
			}
			
			if launchPad:HASMODULE(launchClampModuleName) {
				set launchClampModule to launchPad:GETMODULE(launchClampModuleName).
			}
		}

		// S3 umbilical
		if NOT SHIP:PARTSTAGGED(s3UmbilicalKosTag):EMPTY {
			set s3Umbilical to SHIP:PARTSTAGGED(s3UmbilicalKosTag)[0].
		
			local moduleNames is s3Umbilical:MODULES.
			for idx IN range(0, moduleNames:LENGTH) {
				if moduleNames[idx] = umbilicalAnimModuleName AND idx = s3UmbilicalAnimModuleIndex {
					local pm is s3Umbilical:GETMODULEBYINDEX(idx).
					if pm:HASEVENT(umbilicalEventName) set s3UmbilicalAnimModule to pm.
				}
			}
		}

		//S3 vent
		if NOT SHIP:PARTSTAGGED(s3VentKosTag):EMPTY {
			set s3Vent to SHIP:PARTSTAGGED(s3VentKosTag)[0].
			
			if s3Vent:HASMODULE(ventModuleName) {
				set s3VentModule to s3Vent:GETMODULE(ventModuleName).
			}
		}

		// S2 umbilical
		if NOT SHIP:PARTSTAGGED(s2UmbilicalKosTag):EMPTY {
			set s2Umbilical to SHIP:PARTSTAGGED(s2UmbilicalKosTag)[0].
		
			local moduleNames is s2Umbilical:MODULES.
			for idx IN range(0, moduleNames:LENGTH) {
				if moduleNames[idx] = umbilicalAnimModuleName AND idx = s2UmbilicalAnimModuleIndex {
					local pm is s2Umbilical:GETMODULEBYINDEX(idx).
					if pm:HASEVENT(umbilicalEventName) set s2UmbilicalAnimModule to pm.
				}
			}
		}

		// S2 vent
		if NOT SHIP:PARTSTAGGED(s2VentKosTag):EMPTY {
			set s2Vent to SHIP:PARTSTAGGED(s2VentKosTag)[0].
			
			if s2Vent:HASMODULE(ventModuleName) {
				set s2VentModule to s2Vent:GETMODULE(ventModuleName).
			}
		}

		// S1 umbilicals (4 of these)
		if NOT SHIP:PARTSTAGGED(s1UmbilicalsKosTag):EMPTY {
			set s1Umbilicals to SHIP:PARTSTAGGED(s1UmbilicalsKosTag).

			for u IN s1Umbilicals {
				local moduleNames is u:MODULES.
				for idx IN range(0, moduleNames:LENGTH) {
					if moduleNames[idx] = umbilicalAnimModuleName AND idx = s1UmbilicalsAnimModuleIndex {
						local pm is u:GETMODULEBYINDEX(idx).
						if pm:HASEVENT(s1UmbilicalsEventName) s1UmbilicalsAnimModules:ADD(pm).
					}
				}		
			}
		}

		// S1 vents (8 of these)
		if NOT SHIP:PARTSTAGGED(s1VentsKosTag):EMPTY {
			set s1Vents to SHIP:PARTSTAGGED(s1VentsKosTag).
			
			for vt IN s1Vents {
				if vt:HASMODULE(ventModuleName) {
					s1VentsModules:ADD(vt:GETMODULE(ventModuleName)).
				}		
			}
		}

		return validateAll().
	}
	
}

local function validateAll {

	local success is FALSE.

	local hasLaunchClampEvent is FALSE.
	local hasS1Umbilicals is FALSE.

	set hasLaunchClampEvent to (launchClampModule <> 0 AND launchClampModule:HASEVENT(launchClampEventName)).
	set hasS1Umbilicals to ((NOT s1UmbilicalsAnimModules:EMPTY) AND s1UmbilicalsAnimModules:LENGTH = 4).

	if hasLaunchClampEvent AND hasS1Umbilicals {
		for m in s1UmbilicalsAnimModules {
			if m:HASEVENT(s1UmbilicalsEventName) {
				set success to TRUE.
			}
		}
	}

	if success = TRUE {
		if warningSirenModule <> 0 AND warningSirenModule:HASEVENT(warningEventName) {
			set success to TRUE.
		} ELSE { 		
			set success to FALSE.
		}
	}

	if success = TRUE {
		if s3UmbilicalAnimModule <> 0 AND
		   s3UmbilicalAnimModule:HASEVENT(umbilicalEventName) AND
		   s3VentModule <> 0 AND
		   s3VentModule:HASEVENT(ventEventName) {
				set success to TRUE.
		} ELSE {
			set success to FALSE.
		}
	}

	if success = TRUE {
		if s2UmbilicalAnimModule <> 0 AND
		   s2UmbilicalAnimModule:HASEVENT(umbilicalEventName) AND
		   s2VentModule <> 0 AND
		   s2VentModule:HASEVENT(ventEventName) {
				set success to TRUE.
		} ELSE {
			set success to FALSE.
		}
	}

	return success.

}


// play all the MLP parts at the appropriate time
// if anything failed to initialize properly return false so we can abort the launch
global function playMLP {
	
	// play the warning siren at T-minus 60s
	if mlpStep = 0.0 AND TIME:SECONDS >= tMinus60s {
		if warningSirenModule <> 0 AND warningSirenModule:HASEVENT(warningEventName) {
			warningSirenModule:DOEVENT(warningEventName).
			set mlpStep to 0.1.
			return TRUE.
		} ELSE { 		
			return FALSE.
		}
	}
	
	// at T minus 40, retract the S3 umbilical and turn off its vapor vent
	if mlpStep = 0.1 AND TIME:SECONDS >= tMinus40s {
		if s3UmbilicalAnimModule <> 0 AND
		   s3UmbilicalAnimModule:HASEVENT(umbilicalEventName) AND
		   s3VentModule <> 0 AND
		   s3VentModule:HASEVENT(ventEventName) {

			MissionLog("T-minus 40 seconds").
					
			s3UmbilicalAnimModule:DOEVENT(umbilicalEventName).
			s3VentModule:DOEVENT(ventEventName).

			set mlpStep to 1.0.
			return TRUE.
			
		} ELSE {
			return FALSE.
		}
	}
	
	
	// at T minus 20, retract the S2 umbilical and turn off its vapor vent
	// fire the first stage at minimal throttle for engines checkout
	if mlpStep = 1.0 AND TIME:SECONDS >= tMinus20s {
	
		if s2UmbilicalAnimModule <> 0 AND
		   s2UmbilicalAnimModule:HASEVENT(umbilicalEventName) AND
		   s2VentModule <> 0 AND
		   s2VentModule:HASEVENT(ventEventName) {
			
			MissionLog("IGNITION! T-minus 20").
			
			s2UmbilicalAnimModule:DOEVENT(umbilicalEventName).
			s2VentModule:DOEVENT(ventEventName).
			
			// give the engines enough juice to get the pumps moving
			lock THROTTLE to 0.15.
			
			for f IN enginesStageOneAll {
				f:ACTIVATE.
			}
			
			// close the gate
			set mlpStep to 4.0.
			return TRUE.

		} ELSE {
			return FALSE.
		}
	}
		
	// at T-minus 15 bring up the throttle to some percentage of full thrust
	if mlpStep = 4.0 AND TIME:SECONDS >= tMinus15s {
		local desiredThrottle is 0.35.
		local currentThrottle is THROTTLE.
		local fudge is 0.05.  // this controls the rate of spooling up
		local newThrottle is (1 - fudge) * currentThrottle + (fudge * desiredThrottle).

		lock THROTTLE to newThrottle.
	
		if THROTTLE >= 0.32 {
			set THROTTLE to 0.35.
			set mlpStep to 4.5.
		}

		return TRUE.
	}

	// at T-minus 5 bring up the throttle to full thrust
	if mlpStep = 4.5 AND TIME:SECONDS >= tMinus5s {
		local desiredThrottle is 1.0.
		local currentThrottle is THROTTLE.
		local fudge is 0.1.  // this controls the rate of spooling up
		local newThrottle is (1 - fudge) * currentThrottle + (fudge * desiredThrottle).

		lock THROTTLE to newThrottle.
	
		if THROTTLE >= 0.9 {
			set THROTTLE to 1.0.
			set mlpStep to 5.5.
		}

		return TRUE.
	}
	
	return TRUE.
}

// play the final launch sequence and release the launch clamp
global function launchMLP {
	local success is FALSE.
	local hasLaunchClampEvent is FALSE.
	local hasS1Umbilicals is FALSE.

	set hasLaunchClampEvent to (launchClampModule <> 0 AND launchClampModule:HASEVENT(launchClampEventName)).
	set hasS1Umbilicals to ((NOT s1UmbilicalsAnimModules:EMPTY) AND s1UmbilicalsAnimModules:LENGTH = 4).

	if hasLaunchClampEvent AND hasS1Umbilicals {
	
		for m in s1UmbilicalsAnimModules {
			if m:HASEVENT(s1UmbilicalsEventName) {
				m:DOEVENT(s1UmbilicalsEventName).
				set success to TRUE.
			}
		}
				
		if success {
			launchClampModule:DOEVENT(launchClampEventName).
		}
	}
	
	return success.
}


