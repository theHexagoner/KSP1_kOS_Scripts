@LAZYGLOBAL OFF.

SET CONFIG:IPU TO 2000.0.
local now is TIME(0).

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 	This is a modification of the YAKAP script by github user jefferyharrell (https://github.com/jefferyharrell/YAKAP)    //
//																														  //				
//	It is specifically intended to be used with the Tantares Soyuz rocket craft with that mod's Progress spacecraft as	  //
//	payload. It is also intended to automate the Modular Launchpads Soyuz parts in order to simulate a quasi-realistic	  //
//  launch sequence to the Kerbin Space Station (KSS). The KSS is in a circular 120km orbit, inclined 56.1 degrees from	  //
//	the equator.																										  //
//																														  //			
//	When you run the script it will search for the next launch window, warp to it and then commence launch procedures  	  //
//	At T-60 seconds a klaxon with sound.																				  //
//	At T-40 seconds the large umbilical for the Progress craft and the Stage 3 tanks will retract.						  //
//	At T-20 seconds the small umbilical for the Stage 2 tanks will retract and the main engines will fire				  //
//	At T-15 seconds the main engines should be at a nominal level of thrust												  //
// 	At T-5 seconds the main engines should be at full thrust															  //
//	At T time, the umbilicals for the side boosters will retract and the Soyuz will be released from the pad.			  //
//																														  //
//	At approximately x seconds, the fuel in the side boosters will have been exhausted and they will be decoupled.		  //
//																														  //
// 	At approximately y seconds, the fuel in Blok A will be nearly exhausted and the third stage engine will begin		  //
// 	hot-staging. About 2 seconds later, Blok A will shut down and be decoupled.											  //							
//	                                                                                                                      //
//  This ascent guidance routine will put the Progress into a 95 x 120 km orbit and achieve 51.6 inclination.   		  //
//  TODO: establish orbit within x phase angle of the KSS so rendezvous can be completed within y hours of launch		  
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 	TUNABLE PARAMETERS                                                                                                  ////
//	These params are tuned to work for launching a Soyuz/Progress spacecraft to LKO/KSS									////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// this should be 1/2 the duration (in seconds) of the ascent burn (all stages)
// used to predict launch window for intercepting the KSS orbit
declare local halfLaunchSecs is 160.0.

// The pitch program end altitude is the altitude, in meters, at which we level out to a pitch of 0° off the horizontal.
// this seems to be more or less constrained to the top of the altitude when using the sqrt solution for controlling pitch
declare local pitchProgramEndAltitude is 91500.0.  // meters

// This parameter controls the shape of the ascent curve.
declare local pitchProgramExponent is  0.45.

// This is the airspeed in m/s to begin the pitch program 
declare local pitchProgramAirspeed is 80.0.

// Dynamic pressure, in atmospheres, at which to jettison the payload fairings.
declare local fairingJettisonQ is  0.001.  




////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// Soyuz Rocket                                                                                                       ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Keep track of our engines
declare local enginesStageOneAll is LIST().			// This will include Blok A,B,V,G,D at launch       
declare local enginesStageOneBoosters is LIST().    	// This will include Blok B,V,G,D at launch
declare local engineStageTwo is 0.        				// This is Blok A
declare local engineStageThree is 0.          			// This is Blok I

// keep track of the fuel available to Stage 2
declare local tanksStageTwo is LIST().

// keep track of stage decouplers
declare local decouplerModulesStageOneAll is LIST().	// there are four radial decouplers for dropping S1 boosters
declare local decouplerModuleStageTwo is 0.			// there is a stack decoupler for dropping S2

// these are currently not used for anything, but eventually we will add a routine to separate and deorbit S3
declare local decouplerModuleStageThree is 0.			// there is a stack decoupler for dropping S3
declare local sepratronsStageThree is LIST().			// there are some separator engines on S3 to get it away

// find the launch clamps:
declare local launchClamps is LIST().
declare local launchClampsKosTag is "LAUNCHPAD".
declare local launchClampModuleName_Restock is "ModuleRestockLaunchClamp".

// we need these to launch if there are not MLP toys available
declare local launchClampModules is LIST().	
declare local launchClampEventName is "Release Clamp".


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// Progress Spacecraft                                                                                                ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Keep track of the launch shroud 
declare local launchShroudLower is 0.					// the lower part of the launch shroud, present on all missions
declare local launchShroudsAll is LIST().				// the upper and lower shroud 

// PID controller. Coefficients have been determined empirically.
// This would be used to during Coast mode to supply RCS bursts to keep us from losing too much altitude while in the atmosphere
// TODO: figure out if/how this actually does anything useful
declare local rcsForePIDController  is PIDLOOP(0.001, 0.001, 0.000, 0.0, 1.0).



declare local function GetPartsAndModules {
	parameter hasMLP is false.

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

	// Get a reference to the various launch shroud parts
	if NOT SHIP:PARTSTAGGEDPATTERN("SHROUD"):EMPTY {
		set launchShroudsAll to SHIP:PARTSTAGGEDPATTERN("SHROUD").
	}
	
	if NOT SHIP:PARTSTAGGED("SHROUDL"):EMPTY {
		Set launchShroudLower to SHIP:PARTSTAGGED("SHROUDL")[0].
	}

	if NOT hasMLP {
	
		// Launch clamps and associated modules
		if NOT SHIP:PARTSTAGGED(launchClampsKosTag):EMPTY {
			set launchClamps to SHIP:PARTSTAGGED(launchClampsKosTag).
			for p in launchClamps {
				if p:HASMODULE(launchClampModuleName_Restock) {
					launchClampModules:ADD(p:GETMODULE(launchClampModuleName_Restock)).
				}			
			}
		}
	}

	return validateShip().

}

declare local function validateShip {

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

	If decouplerModuleStageThree = 0 {
		MissionLog("FAIL: Missing S3 decoupler").
        return FALSE.
	}
	
	// THIS CHECK is SPECIFIC to PROGRESS:
	If launchShroudsAll:LENGTH <> 1 OR launchShroudLower = 0 {
		MissionLog("FAIL: Missing launch shroud").
        return FALSE.	
	}

	return TRUE.
}





////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//	MODULAR LAUNCH PADS																									////
//	This is logic for initializing and controlling an MLP Soyuz launch experience                                       ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// PARTS AND MODULE REFERENCES

declare local tMinus60s is 0.
declare local tMinus40s is 0.
declare local tMinus20s is 0.
declare local tMinus15s is 0.
declare local tMinus5s is 0.
declare local tTimeS is 0.

declare local mlpStep is 0.0.
		
declare local launchPad is 0.
declare local launchPadKosTag is "LAUNCHPAD".
declare local launchClampModule is 0.
declare local launchClampModuleName is "LaunchClamp".
declare local launchClampEventName is "Release Clamp".
		
declare local warningSirenModule is 0.
declare local warningSirenModuleName is "PebkacWarningSiren".
declare local warningEventName is "Sound the Alarm".
		
declare local s3Umbilical is 0.
declare local s3UmbilicalKosTag is "S3_UMB".
declare local s3UmbilicalAnimModuleIndex is 6.
declare local s3UmbilicalAnimModule is 0.
		
declare local s3Vent is 0.
declare local s3VentKosTag is "S3_Vent".
declare local s3VentModule is 0.
		
declare local s2Umbilical is 0.
declare local s2UmbilicalKosTag is "S2_UMB".
declare local s2UmbilicalAnimModuleIndex is 3.
declare local s2UmbilicalAnimModule is 0.
		
declare local s2Vent is 0.
declare local s2VentKosTag is "S2_Vent".
declare local s2VentModule is 0.
		
declare local s1Umbilicals is LIST().
declare local s1UmbilicalsKosTag is "S1_UMB".
declare local s1UmbilicalsAnimModuleIndex is 2.
declare local s1UmbilicalsAnimModules is LIST().
declare local s1UmbilicalsEventName is "Retract Clamp Arm".
		
declare local s1Vents is LIST().
declare local s1VentsKosTag is "S1_Vent".
declare local s1VentsModules is LIST().
		
declare local ventModuleName is "MakeSteam".
declare local ventEventName is "Hide Vapor".
declare local umbilicalAnimModuleName is "ModuleAnimateGenericExtra".
declare local umbilicalEventName is "Retract Arm".


// initialize all the parts and modules:
declare local function initializeMLP {
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

		return validateMLP().
	}
	
}

declare local function validateMLP {

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
declare local function playMLP {
	
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
declare local function launchMLP {
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






////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 	LAUNCH PARAMETERS                                                                                                   ////
//	These parametes are generally consistent for any KSS mission														////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local launchToApoapsis is 115000.0. // m
declare local launchToPeriapsis is 115000.0. // m
declare local launchToSemimajorAxis is SHIP:BODY:RADIUS + (launchToPeriapsis + launchToApoapsis) / 2.

// We are launching at the KSS, which is generally in an orbit inclined to 51.6 deg
declare local launchToInclination is VESSEL("The KSS"):OBT:INCLINATION.
declare local targetLAN is VESSEL("The KSS"):OBT:LAN.

// FALSE == we will launch Southwest 
// TRUE == we will launch northeast
declare local launchAtAscendingNode is TRUE.

declare local launchLatitude is SHIP:LATITUDE.		// 45° 17′ 24″ N for Woomerang
declare local launchLongitude is SHIP:LONGITUDE.	// 136° 6′ 36″ E for Woomerang

local function mAngle
{
	PARAMETER a.
	until a >= 0 { set a to a + 360. }
	return MOD(a,360).
}

// Calculates the launch azimuth for a "northerly" launch
declare local function getLaunchAzimuth {

    // This is what our launch azimuth WOULD be if the planet weren't moving.
    declare local launchAzimuthInertial is ARCSIN( COS(launchToInclination) / COS(SHIP:LATITUDE) ).

    // To compensate for the rotation of the planet, we need to estimate the orbital velocity we're going to gain during ascent. 
	// We can ballpark this by assuming a circular orbit at the pitch program end altitude, but there will necessarily be some 
	// very small error, which we will correct during MODE RAISE APOAPSIS.
    declare local vApproximate is SQRT( SHIP:BODY:MU / ( SHIP:BODY:RADIUS + pitchProgramEndAltitude ) ).

    // Construct the components of the launch vector in the rotating frame. 
	// NOTE: In this frame the x axis points north and the y axis points east.
    declare local x is vApproximate * COS(launchAzimuthInertial).
    declare local y is vApproximate * SIN(launchAzimuthInertial) - SHIP:VELOCITY:ORBIT:MAG * COS(SHIP:LATITUDE).

    // Finally, the launch azimuth is the angle of the launch vector we just computed, measured from the x (north) axis: 
    return ARCTAN2(y, x).
}

// Calculates the estimated time (in seconds) until the orbital plane described by the input target_orbit_LAN 
// and target_orbit_inclination will pass over the point defined by the launch pad latitude and longitude
declare local function etaToOrbitPlane {
	PARAMETER is_AN.		// true = return ETA for AN
	local etaSecs is -1.

	// The relative longitude measures the angular difference between the longitude of the launch site 
	// and the longitude of ascending node of an orbit described by the target orbital inclination
	local relativeLong is ARCSIN(TAN(launchLatitude)/TAN(launchToInclination)). 
    
	// if the target orbit is descending:
	if NOT is_AN { set relativeLong to 180 - relativeLong. }

	// adjust for the geographic rotational variance from universal
    local geoLAN is mAngle(targetLAN + relativeLong - BODY:ROTATIONANGLE).
    
	// get the angle between our current geographical longitude and the 
	// geographical longitude where the target orbital plane meets our latitude
	local node_angle is mAngle(geoLAN - launchLongitude).
  
	// calculate how long the rotation of Kerbin will take to rotate us under the target orbit
	set etaSecs to (node_angle / 360) * BODY:ROTATIONPERIOD.

  	return etaSecs.
}

// call this to get the timestamp for the next acceptible launch window
// for now, this should get us very close to being on the same orbital plane as the KSS

// ideally we'd want to launch at the precise time when our circularization burn will 
// get us to within 1km of the KSS at a low relative velocity

declare local function calculateLaunchDetails {
	local eta_to_AN is etaToOrbitPlane(TRUE).
	local eta_to_DN is etaToOrbitPlane(FALSE).
	local laz is getLaunchAzimuth().
		
	local etaSecs is -1.
	
	// figure out the earliest viable option
	if (eta_to_DN < eta_to_AN OR eta_to_AN < halfLaunchSecs) AND eta_to_DN >= halfLaunchSecs {
		// the DN comes first OR 
		// the AN happens first but sooner than we can launch in time
		// in either of these cases the DN does not arrive sooner than we can launch
		set etaSecs to eta_to_DN.
		set laz to mAngle(180 - laz).  

	} ELSE if eta_to_AN >= halfLaunchSecs {
		// the AN happens first, and in time for us to launch
		set etaSecs to eta_to_AN. 

	} ELSE { 
		// how does it get here?
		set etaSecs to eta_to_AN + BODY:ROTATIONPERIOD. 
	}
		
	local launchTime is TIMESTAMP(TIME:SECONDS + etaSecs - halfLaunchSecs).
	return LIST(laz, launchTime).
}


// return the desired pitch bases on given altitude
// expects pitchProgramEndAltitude and pitchProgramExponent local variables
declare local function pitchProgram {
	parameter shipAlt is 0.0.
	return MAX(0.0, 90.0 - 90.0 * (shipAlt / pitchProgramEndAltitude) ^ pitchProgramExponent).
}






// the purpose of this library is to provide a function which returns an azimith that can be used 
// to construct a HEADING that will insert the SHIP into the same orbital plane as a vessel named "The KSS"

// 1 = Get the normal vector of the target orbit.
local kss is VESSEL("The KSS").
local targetNormalVector is V(0,0,0).

// this function returns an azimuth from a vector that can be used to create
// a navball heading with HEADING(azimuth, pitch).
declare local function getAzimuth {
	parameter fromVector.
	
	set fromVector to fromVector:NORMALIZED.

	local east is vcrs(SHIP:UP:VECTOR, SHIP:NORTH:VECTOR).

	local trig_x is vdot(SHIP:NORTH:VECTOR, fromVector).
	local trig_y is vdot(east, fromVector).

	local result is arctan2(trig_y, trig_x).

	if result < 0 {
		return 360 + result.
	} else {
		return result.
	}
}

// this function produces a vector based on the cross between the target normal vector 
// and our current position, velocity and the 
declare local function calculateDirectionalVector {
		
	// 1 = Get the normal vector of the target orbit.
	local targetNormalVector is craftNormal(kss, now).

	// 2 = Get the cross product of the target normal and your radius vector 
	local cross is VCRS(targetNormalVector, posAt(SHIP, now)).

	// 3 = Normalize the result of the cross product, 
	// this gives you the unit vector you can construct a desired velocity vector from
	local cNorm is cross:NORMALIZED.

	// 4 = Calculate the orbital velocity required to reach your target AP given your current PE.
	if velAtAPO = 0 { set velAtAPO to getVelocityForAPO(). }

	// 5 = Multiply the vector from step 3 by the result of step 4, this is your desired direction vector.
	local dirVector is cNorm * velAtAPO.

	// 6 = Exclude the upvector from your orbital velocity vector.
	local excluded is VXCL(SHIP:UP:VECTOR, velAt(SHIP, now)).

	// 7 = Normalize the excluded vector, this is the basis for your current direction vector.
	local xNormed is excluded:NORMALIZED.

	// 8 = Multiply the vector from step 7 by the magnitude of your current orbital velocity.
	if velCurrent = 0.0 { set velCurrent to velAt(SHIP, now):MAG. }
	local xScaled is xNormed * velCurrent.

	// 9 = Subtract the vector resulting from step 8 from the vector resulting from step 5, 
	// this vector gives you the direction along which you should point the vessel
	local vForDir is dirVector - xScaled.

	return vForDir.

}

// then, per iteration:
declare local function getGuidanceAzimuth {
		
	local vForDir is calculateDirectionalVector().
	
	// 10 = convert the vector from step 9 to a compass heading value 
	local newAz is getAzimuth(vForDir).

	return newAz.
}


FUNCTION velAt {
  PARAMETER craft, u_time.
  RETURN VELOCITYAT(craft,u_time):ORBIT.
}

FUNCTION posAt {
  PARAMETER craft, u_time.
  LOCAL b IS ORBITAT(craft,u_time):BODY.
  LOCAL p IS POSITIONAT(craft, u_time).
  IF b <> BODY { SET p TO p - POSITIONAT(b,u_time). }
  ELSE { SET p TO p - BODY:POSITION. }
  RETURN p.
}

FUNCTION craftNormal {
  PARAMETER craft, u_time.
  RETURN VCRS(velAt(craft,u_time),posAt(craft,u_time)).
}

FUNCTION craftRelInc
{
  PARAMETER t, u_time.
  RETURN VANG(craftNormal(SHIP,u_time), craftNormal(t,u_time)).
}

declare local function getRelativeInclination {
	return craftRelInc(kss, now).
}



// Pause the game when the program ends. Useful for unattended launches.
declare local pauseGameWhenFinished is FALSE.

// If useTimeWarp is true, we'll use 2× physics warp during those ascent modes
// where it's safe. Ish. Use at your own risk.
declare local useTimeWarp is FALSE.

// Debugging prints more messages to the screen.
declare local useDebugging is  FALSE.

// keep track of time
declare local tPrevious is TIME(0).
declare local Δt is TIME(0).

// This is a proxy variable for SHIP:SENSORS:ACC. 
// By default, lock this variable to the zero vector.
lock accelerometerReading to V(0.0, 0.0, 0.0).

// The component of the vessel's proper acceleration in the forward direction.
// This is a scalar in m/s².
declare local flightState_α_long is 0.0.

// Maximum dynamic pressure experienced by the vehicle during ascent, in atmospheres.
declare local flightState_MaxQ is 0.0.

// An estimate of aerodynamic drag based on the difference between the expected acceleration (from total thrust and vehicle mass) 
// and the actual acceleration (measured by the on-board accelerometer). We compute this as a moving average to keep the vehicle 
// from getting into a throttle-control feedback loop. 
//
// FD_long = longitudinal component of drag acceleration in m/s².
//
declare local flightState_dragWindow is 5.
declare local flightState_dragData is QUEUE().
declare local flightState_FD_long is 0.0.

// ΣF = Total available thrust, in kilonewtons
declare local flightState_ΣF is 0.0.

// Δv calculations for efficiency, a rough measure of how well this AP works
declare local flightState_ΔvExpended is 0.0. 		// total Δv expended
declare local flightState_ΔvGained is 0.0. 		// Δv gained as orbital velocity
declare local flightState_ΔvEfficiency is 0.0.		// a ratio of Δv expended/gained

declare local modeName is "".

// Keep track of which stage we're on.
declare local currentStage is  0.	// S1 = all boosters, S2 = Blok-A, S3 = Blok-I

// show some stuff when we get into the active guidance
declare local velCurrent is 0.0.
declare local velAtAPO is 0.0.


// Run this once at program startup.
declare local function InitializeFlightState {

    // Do we have an accelerometer part on board? 
    declare local allSensors is LIST().

    LIST SENSORS IN allSensors.
    for s in allSensors {
        if s:HASSUFFIX("TYPE") AND s:TYPE = "ACC" {
            lock accelerometerReading to SHIP:SENSORS:ACC.
            BREAK.
        }
    }

    // Push some zeros onto the drag average calculation queue. This makes it simple to compute a moving average 
	// from time t = 0 without having that average go all crazy from noise in the first few fractions of a second.
    until flightState_dragData:LENGTH = flightState_dragWindow {
        flightState_dragData:PUSH(0.0).
    }

    return.
}

// show the efficiency stats:
declare local showEfficiency is 0.0.
declare local showGuidanceVars is 0.0.

// Update the flight state variables every time we go through the main loop.
declare local function UpdateFlightState {

    set Δt to TIME - tPrevious.
    set tPrevious to TIME.

    // Compute the vessel's current proper acceleration (α), then the component of α in the vehicle's forward direction (α_long).

    declare local flightState_α is accelerometerReading - (-1 * SHIP:UP:FOREVECTOR * (SHIP:BODY:MU / (SHIP:ALTITUDE + SHIP:BODY:RADIUS)^2)).
    set flightState_α_long to VDOT(flightState_α, SHIP:FACING:FOREVECTOR).

    // Compute a moving average of the estimated aerodynamic drag on the vehicle. 
	// We estimate the drag by calculating what our acceleration should be given current thrust vs. current mass and then taking 
	// the difference between the expected acceleration and the actual, measured acceleration. This is not 100% accurate because 
	// of engine gimbaling, but it's close enough.

    if SHIP:ALTITUDE <= 92000 { // 92000 is total atmo height for 2.5x RESCALE
        declare local αExpected is ((THROTTLE * flightState_ΣF) / SHIP:MASS) * SHIP:FACING:FOREVECTOR.
        declare local drag is αExpected - flightState_α.
        declare local drag_long is MIN(0.0, (-1) * VDOT(drag, SHIP:FACING:FOREVECTOR)).
        flightState_dragData:PUSH(drag_long).
        set flightState_FD_long to flightState_FD_long + drag_long/flightState_dragWindow - flightState_dragData:POP()/flightState_dragWindow.
    } ELSE {
        set flightState_FD_long to 0.0.
    }

    // Keep track of the maximum dynamic pressure on the vehicle. When we've
    // passed the point of maximum dynamic pressure, we start looking for a
    // point where it's safe to jettison the launch shroud.
    if SHIP:Q > flightState_MaxQ {
        set flightState_MaxQ to SHIP:Q.
    }

	// The total available thrust is used to compute expended Δv.
    set flightState_ΣF to SHIP:AVAILABLETHRUST.

	when controlAzimuth > 0.0 then { showEfficiency ON. }

	if showEfficiency {
		// Integrate total expended Δv, where Δv = Δv + ΣF × Δt.
		set flightState_ΔvExpended to flightState_ΔvExpended + ((THROTTLE * flightState_ΣF) / SHIP:MASS) * Δt:SECONDS.

		// Calculate Δv gained as orbital velocity in the direction of our launch azimuth. 
		set flightState_ΔvGained to (VDOT(SHIP:VELOCITY:ORBIT, HEADING(controlAzimuth, 0.0):FOREVECTOR)).

		// Calculate flight efficiency as a ratio of Δv gained to Δv expended.
		if flightState_ΔvExpended > 0 AND flightState_ΔvExpended > flightState_ΔvGained {
			set flightState_ΔvEfficiency to MIN(1.0, MAX(0.0, flightState_ΔvGained / flightState_ΔvExpended)).
		}
	}


	set velCurrent to velAt(SHIP, now):MAG.
	set velAtAPO to getVelocityForAPO().

    return.
}

declare local function getVelocityForAPO {
	// use the vis-viva equation:  v^2 = GM * (2/r - 1/a)
	local gm is BODY:MU.
	local cr is SHIP:ALTITUDE + BODY:RADIUS.
	local sma is ((launchToApoapsis + SHIP:OBT:PERIAPSIS) / 2) + BODY:RADIUS.
	local velSq is gm * (2/cr - 1/sma).
	local vel is SQRT(velSq).
	
	return vel.
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// SCREEN FUNCTIONS                                                       											////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// This function turns a number into a string representation with a fixed number of digits after the decimal point. 
// For example, RoundZero(1.6, 2) returns "1.60" with that extra zero as padding.
declare local function RoundZero {
    declare PARAMETER n.
    declare PARAMETER desiredPlaces is 0.

    declare local str is ROUND(n, desiredPlaces):TOSTRING.

    if desiredPlaces > 0 {
        declare local hasPlaces is 0.
        if str:CONTAINS(".") {
            set hasPlaces to str:LENGTH - str:FIND(".") - 1.
        } ELSE {
            set str to str + ".".
        }
        if hasPlaces < desiredPlaces {
            FROM { local i is 0. } until i = desiredPlaces - hasPlaces STEP { set i to i + 1. } DO {
                set str to str + "0".
            }
        }
    }

    return str.
}

declare local function InitializeScreen {
    if useDebugging {
        return.
    }

    CLEARSCREEN.
	showEfficiency OFF.
	showGuidanceVars OFF.

//                   1         2         3         4         5
//         012345678901234567890123456789012345678901234567890
    print "+-----------------------------------------------+ ". //  0
    print "| T+00:00:00                                    | ". //  1
    print "+-----------------------+-----------------------+ ". //  2
    print "| THROTTLE     XXX %    | CUR APO   XXXX.XXX km | ". //  3
    print "| RCS FWD      XXX %    | ORB INCL   XXX.XXX °  | ". //  4
    print "| α_long     XX.XX m/s² | REL INCL   XXX.XXX °  | ". //  5
    print "| G           X.XX      +-----------------------+ ". //  6
    print "| FD_long    XX.XX m/s² | Δv EXPENDED  XXXX m/s | ". //  7
    print "| ΣF_t      XXXXXX kN   | Δv GAINED    XXXX m/s | ". //  8
    print "| ΣF_l      XXXXXX kN   | EFFICIENCY    XXX %   | ". //  9
    print "+-----------------------+-----------------------+ ". // 10
    print "| CUR VEL    XX.XX m/s²                         | ". // 11
    print "| END VEL    XX.XX m/s²                         | ". // 12
	print "| AZ        XXX.XXX °                           | ". // 13
	print "| PITCH     XXX.XXX °                           | ". // 14
    print "+-----------------------+-----------------------+ ". // 15
    print "                                                  ". // 16

    return.
}

declare local function UpdateScreen {
    if useDebugging {
        return.
    }

    if MISSIONTIME > 0 {
        print TIME(MISSIONTIME):CLOCK                               AT ( 4,  1).
    }
    print ("S" + currentStage + ": " + modeName):PADLEFT(34)        AT (13,  1).

    print RoundZero(THROTTLE * 100):PADLEFT(3)                      AT (15,  3).
    print RoundZero(SHIP:CONTROL:FORE * 100):PADLEFT(3)             AT (15,  4).

    if flightState_α_long < 99.99 {
        print RoundZero(flightState_α_long, 2):PADLEFT(6)           AT (12,  5).
    } ELSE {
        print "--.--":PADLEFT(6)                                    AT (12,  5).
    }
    if flightState_α_long/CONSTANT:g0 < 9.99 {
        print RoundZero(flightState_α_long/CONSTANT:g0, 2):PADLEFT(6) AT (12,  6).
    } ELSE {
        print "-.--":PADLEFT(5)                                     AT (12,  6).
    }
    print RoundZero(flightState_FD_long, 2):PADLEFT(6)              AT (12,  7).
    print RoundZero(flightState_ΣF):PADLEFT(6)                    	AT (12,  8).
  
    print RoundZero(SHIP:OBT:APOAPSIS / 1000.0, 3):PADLEFT(8)       AT (36,  3).
    print RoundZero(SHIP:OBT:INCLINATION, 3):PADLEFT(8)    			AT (36,  4).
    print RoundZero(getRelativeInclination(), 3):PADLEFT(7)         AT (37,  5).

    print RoundZero(flightState_ΔvExpended):PADLEFT(4)              AT (39,  7).
    print RoundZero(flightState_ΔvGained):PADLEFT(4)                AT (39,  8).
    print RoundZero(flightState_ΔvEfficiency * 100):PADLEFT(3)      AT (40,  9).

	if showGuidanceVars {
		print RoundZero(velCurrent, 2):PADLEFT(6)		AT (12,  11).
		print RoundZero(velAtAPO, 2):PADLEFT(6)         AT (12,  12).
		print RoundZero(controlAzimuth(), 3):PADLEFT(6)         AT (11,  13).
		print RoundZero(controlPitch, 3):PADLEFT(6)         AT (11,  14).
	}

    return.
}

declare local missionLogLineNumber is 17.

declare local function missionLog {
    declare PARAMETER line.

    if useDebugging {
        print "T+" + TIME(MISSIONTIME):CLOCK + " " + line.
    } ELSE {
        print "T+" + TIME(MISSIONTIME):CLOCK + " " + line AT (0, missionLogLineNumber).
        set missionLogLineNumber to missionLogLineNumber + 1.
    }

    return.
}

declare local function missionDebug {
    declare PARAMETER line.

    if useDebugging {
        missionLog(line).
    }

    return.
}

declare local function FormatTimespan {
	parameter span.

	local yy is span:YEAR:TOSTRING:PADLEFT(2):REPLACE(" ", "0") + "y".
	local dd is span:DAY:TOSTRING:PADLEFT(2):REPLACE(" ", "0") + "d".
	local hh is span:HOUR:TOSTRING:PADLEFT(2):REPLACE(" ", "0") + "h".
	local mm is span:MINUTE:TOSTRING:PADLEFT(2):REPLACE(" ", "0") + "m".
	local ss is span:SECOND:TOSTRING:PADLEFT(2):REPLACE(" ", "0") + "s".

	local fstr is ss.
	
	if span:MINUTE > 0 set fstr to mm + " " + fstr.
	if span:DAY > 0 set fstr to dd + " " + fstr.
	if span:YEAR > 0 set fstr to yy + " " + fstr.

	return fstr:PADLEFT(12).  //  0y 0d 0h 0m 0s
}







wait 0.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// INTERNAL FLIGHT VARIABLES                                                                                          ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Calculate this to know when to launch, in seconds from now.
declare local launchWindowTS is TIME(0). 

// You might want to enable RCS on the launchpad before running this program. If so, we'll respect that.
declare local initialRCSState is RCS.

// You might want to enable SAS on the launchpad before running this program. If so, we'll respect that, too.
declare local initialSASState is SAS.

// This used to control the vehicle's steering.
declare local controlPitch is 0.0. 		// ° above the horizon
declare local controlThrottle is 0.0.   	// 1.0 = full throttle
declare local controlAzimuth is 0.0. 		// ° compass heading

// Track altitude at launch. We use this to know when we have lifted off and cleared moorings.
declare local launchAlt is 0.0. 

// mark timestamp:seconds at various points in the ascent flight-plan
declare local markTimeS is 0.0.

// has Stage 3 started hot-staging?
declare local isStage3HotStaging is FALSE.

// keep track of the current heading
declare local myHeading is HEADING(0.0, 0.0).



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////                                                                        											////
//// STATE MACHINE                                                          											////
////                                                                        											////
//// The heart of this program is a finite-state machine, which means at any given time, the program can be in ONE of 	////
//// several possible modes. Each mode has a transition-in function, a loop function and possibly a transition-out 		////
//// function. 																											////
////																													////
//// The transition-in function is called once when the machine enters that mode; the loop function is called once 		////
//// every time through the main program loop. If there is a transition-out function, it's called once right before 	////
//// we change to another mode.                                                          								////
////                                                                        											////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local stateFunction is {}.


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//	 MODE CALCULATE WINDOW                                                        										////
// 	 Find the next good launch window, and the launch azimuth															////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function ModeGetLaunchWindow {
	
	if NOT SHIP:STATUS = "PRELAUNCH" {
		missionLog("Ship must be on launchpad.").
		set stateFunction to ModeEndProgramTransitionIn@.
		return.	
	}
	
	set modeName to "Calculating Launch Window...".
	missionLog(modeName).

	local launchDetails is calculateLaunchDetails().
	lock controlAzimuth to launchDetails[0].	
	set launchWindowTS to launchDetails[1].

	missionLog("Launch to: " + launchDetails[0] + "°").
	missionLog("Launch at: " + launchWindowTS:FULL).	

	set stateFunction to ModePrelaunchTransitionIn@.
	return.

}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// MODE PRE-LAUNCH                                                          											////
//// Here is where we initialize most of the mission parameters and fire off all the MLP parts for the pre-game show	////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local hasMLP is FALSE.

declare local function ModePrelaunchTransitionIn {
    set modeName to "PRELAUNCH".
    missionLog("MODE to " + modeName).

	set hasMLP to initializeMLP(launchWindowTS:SECONDS).	

	// examine the ship and get all the parts and modules
	if GetPartsAndModules(hasMLP) = FALSE {
		missionLog("FAIL: Active vessel did not meet specs.").
		set stateFunction to ModeEndProgramTransitionIn@.
		return.
	}
	
	// ALL INIT COMPLETE?
	
	if hasMLP {
		WarpToLaunch(launchWindowTS:SECONDS - 70). // @ T-minus 70s
		set stateFunction to ModePrelaunchLoopFunction@.
	} else {
		WarpToLaunch(launchWindowTS:SECONDS).
		set stateFunction to ModeIgnitionLoopFunction@.
	}

    // Capture the height above the ground in prelaunch.
    set launchAlt to ALT:RADAR.
	
	return.

}

// KICK OFF ALL THE MLP TOYS
declare local function ModePrelaunchLoopFunction {
	
	if TIME:SECONDS >= launchWindowTS:SECONDS {
		set stateFunction to ModeLaunchTransitionIn@.
		return.
	}
	
	// when we hit T-minus 60, play the MLP toys
	if TIME:SECONDS >= launchWindowTS:SECONDS - 60 {
		if hasMLP AND (playMLP() = FALSE) {
			set stateFunction to ModeEndProgramTransitionIn@.
			return.		
		}
	}

	return.
}

// DO THIS INSTEAD IF THERE ARE NO MLP PARTS
declare local function ModeIgnitionLoopFunction {

	if TIME:SECONDS >= launchWindowTS:SECONDS {
	
		// Don't try to maneuver
		killSteering().

		set controlThrottle to 1.0.
		lock THROTTLE to controlThrottle.

		// do stuff to light the engines
		for f IN enginesStageOneAll {
			f:ACTIVATE.
		}

		set stateFunction to ModeLaunchTransitionIn@.

	}

	return.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE LAUNCH                                                                                                        	////
// Here is where we will do some final checks that engines are running and making good thrust before launch				////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function ModeLaunchTransitionIn {
    set modeName to "LAUNCH".
    missionLog("MODE to " + modeName).

    // Don't try to maneuver
    killSteering().

	// check out the status of the S1 engines:
    declare local enginesIgnited is TRUE.
    for e IN enginesStageOneAll {
        if e:IGNITION = false {
			set enginesIgnited to false.
			BREAK.
		}
    }

    if NOT enginesIgnited {
		missionLog("S1 ENGINES NO GO!").
		lock THROTTLE to 0.0.
		set stateFunction to ModeEndProgramTransitionIn@.
        return.
    }

	set markTimeS to TIME:SECONDS.
    set stateFunction to ModeLaunchLoop@.
    return.

}

declare local function ModeLaunchLoop  {

	declare local desiredThrust is 1140.0.
	
	// rough: give the engines 5s to spin up
	if TIME:SECONDS >= markTimeS + 5 {
		if SHIP:AVAILABLETHRUST < desiredThrust {
			missionLog("ENGINES NOT ENOUGH GO! " + SHIP:AVAILABLETHRUST ).
			lock THROTTLE to 0.0.
			set stateFunction to ModeEndProgramTransitionIn@.
		} else {
			set stateFunction to ModeLiftoffTransitionIn@.
		}
	}
	
	return.
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE LIFTOFF                                                                                                         ////
// from S1 engines ignition to the vehicle actually moving                                                              ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function ModeLiftoffTransitionIn {
    set modeName to "LIFTOFF".
    missionLog("MODE to " + modeName).
	
    killSteering().

	if hasMLP {
		if launchMLP() = FALSE {
			missionLog("FAIL: Did not launch").
			set stateFunction to ModeEndProgramTransitionIn@.
			return.		
		}
	} else {
		for m in launchClampModules {
			m:DOEVENT(launchClampEventName).
		}
	}

    set stateFunction to ModeLiftoffLoopFunction@.
    return.
}

declare local function ModeLiftoffLoopFunction {
  
    // Wait until we've actually lifted off the pad.
    if ALT:RADAR >= launchAlt {
        set stateFunction to ModeAscentProgramTransitionIn@.
		set currentStage to 1.
        return.
    }

    return.
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE ASCENT PROGRAM                                                                                                  ////
// basically, this gets us from Liftoff to clearing any moorings                                                        ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function ModeAscentProgramTransitionIn {
    set modeName to "ASCENT PROGRAM".
    missionLog("MODE to " + modeName).

    killSteering().

    set stateFunction to ModeAscentProgramLoopFunction@.
    return.
}

declare local function ModeAscentProgramLoopFunction {

    // Wait until the spacecraft clears its own height.
    if ALT:RADAR > launchAlt * 2 {
        set stateFunction to ModeRollProgramTransitionIn@.
        return.
    }

    return.
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE ROLL PROGRAM                                                                                                    ////
// Here we BEGIN rolling such that the vehicle's "up" points in the opposite direction of the launch azimuth. 			////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function ModeRollProgramTransitionIn {
    set modeName to "ROLL PROGRAM".
    missionLog("MODE to " + modeName).
   
	lock controlPitch to 90.0.
	lock myHeading to HEADING(controlAzimuth, controlPitch).
	
    lock STEERING to myHeading.

    set stateFunction to ModeRollProgramLoopFunction@.
    return.
}

declare local function ModeRollProgramLoopFunction {

    // Wait until we reach 70 meters per second.
    if SHIP:AIRSPEED > pitchProgramAirspeed {
        set stateFunction to ModePitchProgramTransitionIn@.
        return.
    }

    return.
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE PITCH PROGRAM                                                                                                   ////
// 																														////
// During the pitch program we command the vehicle to pitch down (toward the horizon) at a rate proportional to our 	////
// vertical speed. Pitch angle is a function of altitude: θ = altitudeⁿ, where altitude is represented as a fraction	////
// of the pitch program end altitude.																					////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function ModePitchProgramTransitionIn {
    set modeName to "PITCH PROGRAM".
    missionLog("MODE to " + modeName).

    lock controlPitch to pitchProgram(SHIP:ALTITUDE).
	lock myHeading to HEADING(controlAzimuth, controlPitch).
	lock STEERING to myHeading.

	// make sure we are at full throttle
    set controlThrottle to 1.0.

	// show the guidance vars on the hud
	showGuidanceVars ON.

    set stateFunction to ModeFlightLoopFunction@.
    return.
}

declare local function ClosedLoopGuidanceTransitionIn {
    set modeName to "CLOSED LOOP".
    missionLog("MODE to " + modeName).

	// make sure we are at full throttle
    set controlThrottle to 1.0.

	lock controlPitch to pitchProgram(SHIP:ALTITUDE).
	lock controlAzimuth to getGuidanceAzimuth().
	lock myHeading to HEADING(controlAzimuth, controlPitch).
	lock STEERING to myHeading.
	

	
	
    set stateFunction to ModeFlightLoopFunction@.
	
    return.
}

// 
declare local function ModeFlightLoopFunction {

    // Trigger fairing jettison if we're past max. Q AND we're at the threshold dynamic pressure.
    if NOT launchShroudsAll:EMPTY { CheckForShroudJettison(). }

    // if ANY of the side-booster engines is out, shut down all the booster engines and jettison them. 
    if currentStage = 1 AND NOT enginesStageOneBoosters:EMPTY {
        for e IN enginesStageOneBoosters {
            if NOT e:IGNITION OR e:FLAMEOUT {
                set stateFunction to ModeBoosterShutdownTransitionIn@.
                return.
            }
        }
    }

	// If Stage 2 is almost finished we need to fire Stage 3.
	if currentStage = 2 AND NOT isStage3HotStaging { 
		if CheckStageThreeHotStage() { 
			set isStage3HotStaging to TRUE.
			set stateFunction to ModeS3IgnitionTransitionIn@.
			return.
		}
	}

	// Blok-A "Core", aka "Stage 2" has shut down
    if currentStage = 2 AND SHIP:MAXTHRUST = 0 {
        set stateFunction to ModeS2ShutdownTransitionIn@.
        return.
    }

	// Blok-A is running and we have hit the end of the pitch program
	// normally this would be impossible?
    if currentStage = 2 AND SHIP:ALTITUDE >= pitchProgramEndAltitude {
        set stateFunction to ModeS2ShutdownTransitionIn@.
        return.
    }

	// Blok-I, aka "Stage 3" has shut down
	// normally this would not happen during the main loop
    if currentStage = 3 AND SHIP:MAXTHRUST = 0 {
        set stateFunction to ModeS3ShutdownTransitionIn@.
        return.
    }

	// Stage 3 is running, pitch program complete, APO target not yet achieved
    if currentStage = 3 AND SHIP:APOAPSIS < launchToApoapsis AND SHIP:ALTITUDE >= pitchProgramEndAltitude  {
        set stateFunction to ModeRaiseApoapsisTransitionIn@.
        return.
    }

	// Stage 3 is running, target APO achieved, so coast to APO
    if currentStage = 3 AND SHIP:APOAPSIS >= launchToApoapsis {
        set stateFunction to ModePoweredCoastTransitionIn@.
        return.
    }
	
    return.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE BOOSTER SHUTDOWN                                                                                                ////
// The boosters have shut down and we need to jettison them. 			                                    			////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function ModeBoosterShutdownTransitionIn {
    set modeName to "BOOSTER SHUTDOWN".
    missionLog("MODE to " + modeName).

    stopTimeWarp().
    killSteering().

    set stateFunction to ModeBoosterShutdownLoopFunction@.
    return.
}

declare local function ModeBoosterShutdownLoopFunction {
    
	// any logic/operations that need time to evolve would go here
	killSteering().

    set stateFunction to ModeBoosterSeparationTransitionIn@.
    return.
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE BOOSTER SEPARATION                                                                                              ////
// Korolev would be proud												                                    			////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function ModeBoosterSeparationTransitionIn {
    set modeName to "BOOSTER SEPARATION".
    missionLog("MODE to " + modeName).

    set markTimeS to TIME:SECONDS.
    stopTimeWarp().

    killSteering().

    set stateFunction to ModeBoosterSeparationLoopFunction@.
    return.
}

declare local function ModeBoosterSeparationLoopFunction {

    killSteering().

	// don't be hasty...wait half a second
    if TIME:SECONDS - markTimeS >= 0.5 {
    	
		// this will decouple the radial boosters
		for f IN decouplerModulesStageOneAll {
			f:DOEVENT("Decouple").
		}
		
		missionLog("Decoupling Boosters").

		enginesStageOneBoosters:CLEAR().
		enginesStageOneAll:CLEAR().
		
		set currentStage to 2.
		missionLog("Set current stage to 2").

        set stateFunction to ClosedLoopGuidanceTransitionIn@.
		missionLog("Start closed loop guidance").

        return.
    }

    return.
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE S3 IGNITION                                                                                                     ////
// The stage 3 engine hot-stages for two seconds prior to S2 cutoff to account for ullage								////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function ModeS3IgnitionTransitionIn {
    set modeName to "S3 IGNITION".
    missionLog("MODE to " + modeName).

	killSteering().

	engineStageThree:ACTIVATE.
	set markTimeS to TIME:SECONDS.

    set stateFunction to ModeS3IgnitionLoopFunction@.
    return.
}

declare local function ModeS3IgnitionLoopFunction {
	
	if engineStageThree:IGNITION OR 
		TIME:SECONDS >= markTimeS + 2 OR 
		engineStageTwo:FLAMEOUT {
	    set stateFunction to ModeS3IgnitionTransitionOut@.
	}

    return.
}

declare local function ModeS3IgnitionTransitionOut {

	if NOT engineStageThree:IGNITION {
		missionLog("S3 Engine Failure!").
		set stateFunction to ModeEndProgramTransitionIn@.
		return.
	}

	set stateFunction to ModeS2ShutdownTransitionIn@.
    return.
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE S2 Shutdown                                                                                              		////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function ModeS2ShutdownTransitionIn {
    set modeName to "S2 SHUTDOWN".
    missionLog("MODE to " + modeName).

    stopTimeWarp().
	killSteering().
	
	set markTimeS to TIME:SECONDS.

    set stateFunction to ModeS2ShutdownLoopFunction@.
    return.
}

declare local function ModeS2ShutdownLoopFunction {

	killSteering().
	
	if TIME:SECONDS - markTimeS >= 2.0 OR engineStageTwo:FLAMEOUT {
		engineStageTwo:SHUTDOWN.
	    set stateFunction to ModeS2SeparationTransitionIn@.
		return.
	}

    return.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE S2 Separation                                                                                          			////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function ModeS2SeparationTransitionIn {
    set modeName to "S2 SEPARATION".
    missionLog("MODE to " + modeName).
    
	set stateFunction to ModeS2SeparationLoopFunction@.
    return.
}

declare local function ModeS2SeparationLoopFunction {

	// hot stage, if possible
	if decouplerModuleStageTwo:HASEVENT("DECOUPLE") {
		decouplerModuleStageTwo:DOEVENT("Decouple").
		
		// stage 3 should already be running ~ 100% thrust
		set currentStage to 3.
	
		// at this point there are only a few possible paths:

		// we are not done pitching
		if SHIP:ALTITUDE < pitchProgramEndAltitude {
			set stateFunction to ClosedLoopGuidanceTransitionIn@.
			return.
		}

		// 
		if SHIP:ALTITUDE >= pitchProgramEndAltitude AND SHIP:APOAPSIS < launchToApoapsis {
			set stateFunction to ModeRaiseApoapsisTransitionIn@.
			return.
		}

		if SHIP:ALTITUDE >= pitchProgramEndAltitude AND SHIP:APOAPSIS >= launchToApoapsis {
			set stateFunction to ModePoweredCoastTransitionIn@.
			return.
		}
	}

	missionLog("WRONG TROUSERS GROMMIT!").
}



////////////////////////////////////////////////////////////////////////////////
// MODE RAISE APOAPSIS /////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

// In this mode we've finished the pitch program but our apoapsis is still too
// low, so we keep burning the second stage until our apoapsis is correct. Along
// the way, we correct the inclination error that resulted from our approximate
// calculation of the launch azimuth.

declare local function ModeRaiseApoapsisTransitionIn {
    set modeName to "RAISE APOAPSIS".
    missionLog("MODE to " + modeName).

    lock controlPitch to 0.0.
    lock STEERING to HEADING(controlAzimuth, controlPitch).

	// make sure we are full-throttle
    set controlThrottle TO 1.0.

    StartTimeWarp().

    set stateFunction to ModeRaiseApoapsisLoopFunction@.
    return.
}

declare local function ModeRaiseApoapsisLoopFunction {

	// both of these should have already happened
    if NOT launchShroudsAll:EMPTY { CheckForShroudJettison(). }

	// only a few things are possible once we are this far along:

	// stage 2 was somehow still running when we hit the end of the pitch program
    if currentStage = 2 AND SHIP:MAXTHRUST = 0 {
        set stateFunction to ModeS2ShutdownTransitionIn@.
        return.
    }

	// stage 3 has died early
    if currentStage = 3 AND SHIP:MAXTHRUST = 0 {
        set stateFunction to ModeS3ShutdownTransitionIn@.
        return.
    }

	// stage 3 has created an orbit with the target AP
    if currentStage = 3 AND SHIP:APOAPSIS >= launchToApoapsis {
        set stateFunction to ModeS3ShutdownTransitionIn@.
        return.
    }

	// keep on burning at the horizon
    return.
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE S3 SHUTDOWN 																									////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function ModeS3ShutdownTransitionIn {
    set modeName to "S3 SHUTDOWN".
    missionLog("MODE to " + modeName).

    stopTimeWarp().

    set controlThrottle to 0.0.
	killSteering().

    set markTimeS to TIME:SECONDS.

    set stateFunction to ModeS3ShutdownLoopFunction@.
    return.
}

declare local function ModeS3ShutdownLoopFunction {

    if THROTTLE = 0.0 AND TIME:SECONDS >= markTimeS + 2.0 {

        if SHIP:APOAPSIS < launchToApoapsis {
			missionLog("MISSION FAIL").
            set stateFunction to ModeEndProgramTransitionIn@.
            return.
        }

        if SHIP:APOAPSIS >= launchToApoapsis AND SHIP:ALTITUDE < 92000.0 {
            set stateFunction to ModePoweredCoastTransitionIn@.
            return.
        }

        if SHIP:APOAPSIS >= launchToApoapsis AND SHIP:ALTITUDE >= 92000.0 {
            set stateFunction to ModeComputeApoapsisManeuverTransitionIn@.
            return.
        }

        set stateFunction to ModeEndProgramTransitionIn@.
		return.
    }

    return.
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE POWERED COAST 																									////
// In this mode our apoapsis is correct but we're still inside the atmosphere, so we do a powered coast to space using 	////
// RCS thrust to counteract atmospheric drag. Obviously if the stage has no forward RCS thrust then we'll fall back		////
// somewhat, but we should still end up close to our desired orbit.                                                     ////  
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function ModePoweredCoastTransitionIn {
    set modeName to "POWERED COAST".
    missionLog("MODE to " + modeName).

	// TODO: replace this with closed-loop guidance
    lock controlPitch to 0.0.
    lock STEERING to SHIP:SRFPROGRADE.

    set controlThrottle to 0.0.

    RCS ON.
    set rcsForePIDController:SETPOINT to launchToApoapsis.
    set SHIP:CONTROL:FORE to rcsForePIDController:UPDATE(TIME:SECONDS, ALT:APOAPSIS).

    StartTimeWarp().

    set stateFunction to ModePoweredCoastLoopFunction@.
    return.
}

declare local function ModePoweredCoastLoopFunction {

    if SHIP:ALTITUDE >= 92000.0 {
        set stateFunction to ModePoweredCoastTransitionOut@.
        return.
    }

	// both of these should have already happened
    if NOT launchShroudsAll:EMPTY { CheckForShroudJettison(). }

	// give it a boost
    set SHIP:CONTROL:FORE to rcsForePIDController:UPDATE(TIME:SECONDS, ALT:APOAPSIS).

    return.
}

declare local function ModePoweredCoastTransitionOut {

    stopTimeWarp().

    set SHIP:CONTROL:FORE to 0.0.
    set SHIP:CONTROL:NEUTRALIZE to TRUE.
    set RCS to initialRCSState.

    Set stateFunction to ModeComputeApoapsisManeuverTransitionIn@.
    return.
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE COMPUTE APOAPSIS MANEUVER 																						////
//																														////
// Here we merely calculate the apoapsis maneuver necessary to put us into the target orbit. We create a maneuver 		////
// node for it, but we don't try to execute it or anything. MechJeb does a fine job of executing maneuver nodes.		////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function ModeComputeApoapsisManeuverTransitionIn {
    set modeName to "COMPUTE APOAPSIS MANEUVER".
    missionLog("MODE to " + modeName).

    declare local v1 is SQRT( SHIP:BODY:MU * ( (2/(SHIP:BODY:RADIUS + ALT:APOAPSIS)) - (1/SHIP:ORBIT:SEMIMAJORAXIS) ) ).
    declare local v2 is SQRT( SHIP:BODY:MU * ( (2/(SHIP:BODY:RADIUS + ALT:APOAPSIS)) - (1/launchToSemimajorAxis) ) ).
    declare local Δv is v2 - v1.

    declare local apoapsisManeuver to NODE( TIME:SECONDS + ETA:APOAPSIS, 0.0, 0.0, Δv).
    ADD apoapsisManeuver.

    set stateFunction to ModeNullRatesTransitionIn@.
    return.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE NULL RATES 																										////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function ModeNullRatesTransitionIn {
    set modeName to "NULL RATES".
    missionLog("MODE to " + modeName).

    set SHIP:CONTROL:NEUTRALIZE to TRUE.

	set controlThrottle to 0.0.
    killSteering().
	
    set stateFunction to ModeNullRatesLoopFunction@.
    return.
}

declare local function ModeNullRatesLoopFunction {
    // How about NOT spinning out of control?
    if SHIP:ANGULARVEL:MAG < 0.010 {
        set stateFunction to ModeEndProgramTransitionIn@.
        return.
    }
	
	return.
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE END PROGRAM 																									////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function ModeEndProgramTransitionIn {
    set modeName to "END PROGRAM".
    missionLog("MODE to " + modeName).

    UNLOCK THROTTLE.
    UNLOCK STEERING.
    set SHIP:CONTROL:NEUTRALIZE to TRUE.
	set SHIP:CONTROL:PILOTMAINTHROTTLE to 0.0.
    set RCS to initialRCSState.
	set SAS to initialSASState.

    missionLog("CTRL-C to END PROGRAM").

    if pauseGameWhenFinished AND NOT ABORT {
        KUNIVERSE:PAUSE().
    }

    set stateFunction to {}.
    return.
}




////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// TIMEWARP CONTROL                                                       											////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

declare local function StartTimeWarp {
    if useTimeWarp AND KUNIVERSE:TIMEWARP:RATE <> 2.0 {
        set KUNIVERSE:TIMEWARP:MODE to "PHYSICS".
        set KUNIVERSE:TIMEWARP:RATE to 2.0.
    }
}

declare local function stopTimeWarp {
    KUNIVERSE:TIMEWARP:CANCELWARP().
}





////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// UTILITY FUNCTIONS                                                       											////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// hold current attitude
declare local function killSteering {
	set STEERING to "KILL".
}

// Can we jettison the launch shroud?
declare local function CheckForShroudJettison {

    // Trigger fairing jettison if we're past max. Q AND we're at the threshold dynamic pressure.
    if NOT launchShroudsAll:EMPTY AND SHIP:Q < flightState_MaxQ AND SHIP:Q < fairingJettisonQ {
		for f IN launchShroudsAll {
			if f:HASMODULE("ModuleProceduralFairing") {
                f:GETMODULE("ModuleProceduralFairing"):DOEVENT("Deploy").
            }
		}
		
		launchShroudsAll:CLEAR().
		set launchShroudLower to 0.

    }
	
	return.
}

// Can we start hot-staging stage 3?
declare local function CheckStageThreeHotStage {

	// figure out how much burn time is left in stage two
	// if it's 2 seconds or less, return true
	
	// the mass flow rate of a RD-108 in vaccuum is ~81.256 kg/s
	// thus 2 seconds of mass flow = 0.1625 tons of propellant
	// one ton of stock propellant is comprised of 90 units of LF + 110 units of OX
	// 90 x .1625 = 14.625 units of LF
	// 110 x .1625 = 17.875 units of OX
	
	declare local fuelRemaining is 0.0.
	
	// get the remaining fuel content of stage 2 tanks
	for f IN tanksStageTwo {
		for r IN f:RESOURCES {
			if r:NAME = "LIQUIDFUEL" {
				set fuelRemaining to fuelRemaining + r:AMOUNT.
				BREAK.
			}
		}
	}
	
	if fuelRemaining <= 15.0 {
		missionLog("Stage 2 tanks nearly exhausted").
		return TRUE.
	} else {
		return FALSE.
	}
}

// HeadingOfVector returns the heading of given vector 
declare local function HeadingOfVector { 
	PARAMETER vecT.

	local east is VCRS(SHIP:UP:VECTOR, SHIP:NORTH:VECTOR).
	local trig_x is VDOT(SHIP:NORTH:VECTOR, vecT).
	local trig_y is VDOT(east, vecT).
	local result is ARCTAN2(trig_y, trig_x).

	if result < 0 { set result to 360 + result.} 
	
	return result.
}

// Wrapper for KUNIVERSE:TIMEWARP:WARPTO(timestamp).
declare local function WarpToLaunch
{
	PARAMETER newTS. // seconds since epoch
	
	if newTS - TIME:SECONDS > 5 {
		missionLog("Waiting for Launch Window to open").
		
		until WARPMODE = "RAILS" { 
			set WARPMODE to "RAILS". 
			set WARP to 1. 
			wait 0.2. 
		}
	
		kuniverse:TimeWarp:WARPTO(newTS).

	} ELSE {
		missionLog("T-minus " + (TIME:SECONDS - newTS)).
	
	}
	
	return.
}





////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// ABORT                                                                  											////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
ON ABORT {

    stopTimeWarp().
    missionLog("ABORT").	
	
	// TODO: self-destruct? That might be cool.

	return.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// MAIN LOOP                                                              											////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// prevent the ship from doing unexpected stuff when coming off autopilot
set SHIP:CONTROL:PILOTMAINTHROTTLE to 0.0.

// This is kind of a hack to damp roll oscillations.
set STEERINGMANAGER:ROLLTS to 5.0.

// also, keep the craft from rolling around slowly after lauch:
set STEERINGMANAGER:ROLLCONTROLANGLERANGE to 180.

// start off with engines idle
LOCK THROTTLE to 0.0.

// go and get a launch window
set stateFunction to ModeGetLaunchWindow@.

// set up all the stuff we will track in the UI
InitializeFlightState().

// initialize the UI
InitializeScreen().

// but don't bother updating it until we actually do something
// TODO: just return whether or not anything has changed inside UpdateFlightState() 
local showUpdate is FALSE.

// run until the user quits it
until FALSE {
	set now to TIME.

	// if we've gone off, start updating the UI
	if showUpdate = FALSE AND stateFunction = ModeLiftoffTransitionIn@ {
		set showUpdate to TRUE.
	}

// TODO: just return whether or not anything has changed inside UpdateFlightState() 
	if showUpdate = TRUE {
		// update the current flight state for the UI
		UpdateFlightState().
		UpdateScreen().
	}    
	
	// enter the next pass through the state machine
	stateFunction:CALL().

    // Yield until the next physics tick.
    wait 0.
}