@LAZYGLOBAL OFF.

// this is an ascent guidance script to launch Soyuz/Progress to the KSS from Woomerang

// set this lower after we make this run more efficiently
SET CONFIG:IPU TO 400.0.

// track the time at the last point when we let KSP have control
global nowLastTick is TIME(0).  

// Pause the game when the program ends. Useful for unattended launches.
global pauseGameWhenFinished is FALSE.

// If useTimeWarp is true, we'll use 2× physics warp during those ascent modes
// where it's safe. Ish. Use at your own risk.
global useTimeWarp is FALSE.

// our target:
GLOBAL KSS is VESSEL("The KSS").

print "Loading parts and modules...".
RUNONCEPATH("vehicle.ks").

print "Starting guidance program...".
RUNONCEPATH("guido.ks").

print "Initializing display logic...".
RUNONCEPATH("ui_flightState.ks").

wait 3.



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// INTERNAL FLIGHT VARIABLES                                                                                          ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Calculate this to know when to launch into orbital plane of KSS.
local launchWindowTS is TIME(0). 

// when the script ends put RCS back where we found it
local initialRCS is RCS.

// when the script ends put RCS back where we found it
local initialSAS is SAS.

// This used to control the vehicle's steering.
global controlPitch is 0.0. 		// ° above the horizon
global controlThrottle is 0.0.   	// 1.0 = full throttle
global controlAzimuth is 0.0. 		// ° compass heading

// keep track of the current heading
local myHeading is HEADING(0.0, 0.0).

// Track altitude at launch. We use this to know when we have lifted off and cleared moorings.
local launchAlt is 0.0. 

// mark timestamp:seconds at various points in the ascent flight-plan
local markTimeS is 0.0.

// has Stage 3 started hot-staging?
local isStage3HotStaging is FALSE.

// Dynamic pressure, in atmospheres, at which to jettison the payload fairings.
local fairingJettisonQ is  0.001.  



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 	STATE MACHINE                                                                                                         //
//                                                                                                                        //
// 	The heart of this program is a finite-state machine, which means at any given time, the program can be in ONE of      //
// 	several possible modes. Each mode has a transition-in function, a loop function and possibly a transition-out         //
// 	function. 																											  //
//                                                                                                                        //
// 	The transition-in function is called once when the machine enters that mode;                                          //
// 	The loop function is called once every time through the main program loop.                                            //
// 	If there is a transition-out function, it's called once right before we change to another mode.                       //
//                                                                                                                        //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

local stateFunction is {}.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  MODE CALCULATE WINDOW                                                                                                 //
// 	Find the next good launch window, and the launch azimuth                                                              //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

local function ModeGetLaunchWindow {
	
	if NOT SHIP:STATUS = "PRELAUNCH" {
		missionLog("Ship must be on launchpad.").
		set stateFunction to ModeEndProgramTransitionIn@.
		return.	
	}
	
	set modeName to "Calculating Launch Window...".
	missionLog(modeName).

	local launchDetails is calculateLaunchDetails().
	set controlAzimuth to launchDetails[0].	
	set launchWindowTS to launchDetails[1].

	missionLog("Launch to: " + RoundZero(launchDetails[0], 2) + "°").
	missionLog("Launch at: " + launchWindowTS:FULL).	

	set stateFunction to ModePrelaunchTransitionIn@.
	return.

}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// MODE PRE-LAUNCH                                                          											////
//// Here is where we initialize most of the mission parameters and fire off all the MLP parts for the pre-game show	////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

local hasMLP is FALSE.
local soundWarning is FALSE.

local function ModePrelaunchTransitionIn {
    set modeName to "PRELAUNCH".
    // missionLog("MODE to " + modeName).

	// examine the ship and get all the parts and modules
	if GetPartsAndModules() = FALSE {
		missionLog("FAIL: Active vessel did not meet specs.").
		set stateFunction to ModeEndProgramTransitionIn@.
		return.
	}
	
	// ALL INIT COMPLETE?
	set hasMLP to NOT SHIP:PARTSTAGGED("PREGAME"):EMPTY.
	
	when SHIP:SENSORS:LIGHT >= 0.75 then LIGHTS OFF.
	when SHIP:SENSORS:LIGHT <= 0.85 then LIGHTS ON.
	
	if hasMLP {
		missionLog("Found MLP").
		WarpToLaunch(launchWindowTS:SECONDS - 70). // @ T-minus 70s
		set stateFunction to ModePrelaunchLoopFunction@.
	} else {
		WarpToLaunch(launchWindowTS:SECONDS - 5).
		set stateFunction to ModeIgnitionLoopFunction@.
	}

    // Capture the height above the ground in prelaunch.
    set launchAlt to ALT:RADAR.
	
	return.

}

// KICK OFF ALL THE MLP TOYS
local function ModePrelaunchLoopFunction {
	
	if TIME:SECONDS >= launchWindowTS:SECONDS {
		set stateFunction to ModeLaunchTransitionIn@.
		return.
	}
	
	// make sure we are at full main throttle
	if TIME:SECONDS >= launchWindowTS:SECONDS - 5 {
		set controlThrottle to 1.0.
		lock THROTTLE to controlThrottle.
		return.
	}
	
	// TODO: redo the plugin so this is an action we can control with KAL
	// when we hit T-MINUS 60, play the SIREN
	if TIME:SECONDS >= launchWindowTS:SECONDS - 60 AND soundWarning {
		set soundWarning to FALSE.
		if warningSirenModule <> 0 AND warningSirenModule:HASEVENT(warningEventName) 
			warningSirenModule:DOEVENT(warningEventName).
	}
	
	// when we hit T-minus 70, play the MLP toys
	if TIME:SECONDS >= launchWindowTS:SECONDS - 70 {
		if hasMLP {
			set hasMLP to FALSE.
			set soundWarning to TRUE.
			local p is SHIP:PARTSTAGGED("PREGAME")[0].
			local m is p:GETMODULE("ModuleRoboticController").
			m:DOACTION("Play Sequence", TRUE).
			return.		
		}
	}

	return.
}

// NO MLP, so just fire engines
local function ModeIgnitionLoopFunction {

	if TIME:SECONDS >= launchWindowTS:SECONDS - 5 {
	
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

local function ModeLaunchTransitionIn {
    set modeName to "LAUNCH".
    // missionLog("MODE to " + modeName).

    // Don't try to maneuver
    killSteering().

	// check out the status of the S1 engines:
    local enginesIgnited is TRUE.
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

    set stateFunction to ModeLaunchLoop@.
    return.

}

local function ModeLaunchLoop  {

	local desiredThrust is 1140.0.
	
	// rough: give the engines 5s to spin up
	if TIME:SECONDS >= launchWindowTS:SECONDS {
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

local function ModeLiftoffTransitionIn {
    set modeName to "LIFTOFF".
    // missionLog("MODE to " + modeName).
	
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

local function ModeLiftoffLoopFunction {
  
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

local function ModeAscentProgramTransitionIn {
    set modeName to "ASCENT PROGRAM".
    // missionLog("MODE to " + modeName).

    killSteering().

    set stateFunction to ModeAscentProgramLoopFunction@.
    return.
}

local function ModeAscentProgramLoopFunction {

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

local function ModeRollProgramTransitionIn {
    set modeName to "ROLL PROGRAM".
    // missionLog("MODE to " + modeName).
   
	set controlPitch to 90.0.
	set myHeading to HEADING(controlAzimuth, controlPitch).
    set STEERING to myHeading.

    set stateFunction to ModeRollProgramLoopFunction@.
    return.
}

local function ModeRollProgramLoopFunction {

    if SHIP:AIRSPEED > 80.0 {
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

local function ModePitchProgramTransitionIn {
    set modeName to "PITCH PROGRAM".
    // missionLog("MODE to " + modeName).

	// what's the worst that could happen?
	CLOSED_LOOP ON.

	// make sure we are at full throttle
    set controlThrottle to 1.0.

    set stateFunction to ModeFlightLoopFunction@.
    return.
}

// TODO: maybe we can just used closed loop all the way up
local function ClosedLoopGuidanceTransitionIn {
    set modeName to "CLOSED LOOP".
    // missionLog("MODE to " + modeName).

	CLOSED_LOOP ON.

	// make sure we are at full throttle
    set controlThrottle to 1.0.

    set stateFunction to ModeFlightLoopFunction@.
	
    return.
}

// 
local function ModeFlightLoopFunction {

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
		
	UpdateGuido(SHIP:ALTITUDE).

	set controlPitch to GUIDO:PITCH.
	set controlAzimuth to GUIDO:AZIMUTH.
	set myHeading to HEADING(controlAzimuth, controlPitch).
	set STEERING to myHeading.
	
    return.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE BOOSTER SHUTDOWN                                                                                                ////
// The boosters have shut down and we need to jettison them. 			                                    			////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

local function ModeBoosterShutdownTransitionIn {
    set modeName to "BOOSTER SHUTDOWN".
    // missionLog("MODE to " + modeName).

    stopTimeWarp().
    killSteering().

    set stateFunction to ModeBoosterShutdownLoopFunction@.
    return.
}

local function ModeBoosterShutdownLoopFunction {
    
	// any logic/operations that need time to evolve would go here
	killSteering().

    set stateFunction to ModeBoosterSeparationTransitionIn@.
    return.
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE BOOSTER SEPARATION                                                                                              ////
// Korolev would be proud												                                    			////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

local function ModeBoosterSeparationTransitionIn {
    set modeName to "BOOSTER SEPARATION".
    // missionLog("MODE to " + modeName).

    set markTimeS to TIME:SECONDS.
    stopTimeWarp().

    killSteering().

    set stateFunction to ModeBoosterSeparationLoopFunction@.
    return.
}

local function ModeBoosterSeparationLoopFunction {

    killSteering().

	// don't be hasty...wait half a second
    if TIME:SECONDS - markTimeS >= 0.5 {
    
		// this will decouple the radial boosters
		for f IN decouplerModulesStageOneAll {
			f:DOEVENT("Decouple").
		}

		enginesStageOneBoosters:CLEAR().
		enginesStageOneAll:CLEAR().
		
		set currentStage to 2.

//        set stateFunction to ClosedLoopGuidanceTransitionIn@.
		set stateFunction to ModePitchProgramTransitionIn@.
        return.
    }

    return.
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE S3 IGNITION                                                                                                     ////
// The stage 3 engine hot-stages for two seconds prior to S2 cutoff to account for ullage								////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

local function ModeS3IgnitionTransitionIn {
    set modeName to "S3 IGNITION".
    // missionLog("MODE to " + modeName).

	killSteering().

	engineStageThree:ACTIVATE.
	set markTimeS to TIME:SECONDS.

    set stateFunction to ModeS3IgnitionLoopFunction@.
    return.
}

local function ModeS3IgnitionLoopFunction {
	
	if engineStageThree:IGNITION OR 
		TIME:SECONDS >= markTimeS + 2 OR 
		engineStageTwo:FLAMEOUT {
	    set stateFunction to ModeS3IgnitionTransitionOut@.
	}

    return.
}

local function ModeS3IgnitionTransitionOut {

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

local function ModeS2ShutdownTransitionIn {
    set modeName to "S2 SHUTDOWN".
    // missionLog("MODE to " + modeName).

    stopTimeWarp().
	killSteering().
	
	set markTimeS to TIME:SECONDS.

    set stateFunction to ModeS2ShutdownLoopFunction@.
    return.
}

local function ModeS2ShutdownLoopFunction {

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

local function ModeS2SeparationTransitionIn {
    set modeName to "S2 SEPARATION".
    // missionLog("MODE to " + modeName).
    
	set stateFunction to ModeS2SeparationLoopFunction@.
    return.
}

local function ModeS2SeparationLoopFunction {

	// hot stage, if possible
	if decouplerModuleStageTwo:HASEVENT("DECOUPLE") {
		decouplerModuleStageTwo:DOEVENT("Decouple").
		
		// stage 3 should already be running ~ 100% thrust
		set currentStage to 3.
	
		// at this point there are only a few possible paths:

		// we are not done pitching
		if SHIP:ALTITUDE < pitchProgramEndAltitude {
//			set stateFunction to ClosedLoopGuidanceTransitionIn@.
			set stateFunction to ModePitchProgramTransitionIn@.

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

local function ModeRaiseApoapsisTransitionIn {
    set modeName to "RAISE APOAPSIS".
    // missionLog("MODE to " + modeName).

	// make sure we are full-throttle
    set controlThrottle TO 1.0.

    StartTimeWarp().

    set stateFunction to ModeRaiseApoapsisLoopFunction@.
    return.
}

local function ModeRaiseApoapsisLoopFunction {

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
	UpdateGuido(SHIP:ALTITUDE).

	set controlPitch to GUIDO:PITCH.
	set controlAzimuth to GUIDO:AZIMUTH.
	set myHeading to HEADING(controlAzimuth, controlPitch).
	set STEERING to myHeading.

    return.
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE S3 SHUTDOWN 																									////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

local function ModeS3ShutdownTransitionIn {
    set modeName to "S3 SHUTDOWN".
    // missionLog("MODE to " + modeName).

    stopTimeWarp().

    set controlThrottle to 0.0.
	killSteering().

    set markTimeS to TIME:SECONDS.

    set stateFunction to ModeS3ShutdownLoopFunction@.
    return.
}

local function ModeS3ShutdownLoopFunction {

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

local function ModePoweredCoastTransitionIn {
    set modeName to "POWERED COAST".
    // missionLog("MODE to " + modeName).



    set controlThrottle to 0.0.

    RCS ON.
    set rcsForePIDController:SETPOINT to launchToApoapsis.
    set SHIP:CONTROL:FORE to rcsForePIDController:UPDATE(TIME:SECONDS, ALT:APOAPSIS).

    StartTimeWarp().

    set stateFunction to ModePoweredCoastLoopFunction@.
    return.
}

local function ModePoweredCoastLoopFunction {

    if SHIP:ALTITUDE >= 92000.0 {
        set stateFunction to ModePoweredCoastTransitionOut@.
        return.
    }

	// both of these should have already happened
    if NOT launchShroudsAll:EMPTY { CheckForShroudJettison(). }

	// give it a boost
    set SHIP:CONTROL:FORE to rcsForePIDController:UPDATE(TIME:SECONDS, ALT:APOAPSIS).

	UpdateGuido(SHIP:ALTITUDE).

	set controlPitch to GUIDO:PITCH.
	set controlAzimuth to GUIDO:AZIMUTH.
	set myHeading to HEADING(controlAzimuth, controlPitch).
	set STEERING to myHeading.

    return.
}

local function ModePoweredCoastTransitionOut {

    stopTimeWarp().

    set SHIP:CONTROL:FORE to 0.0.
    set SHIP:CONTROL:NEUTRALIZE to TRUE.
    set RCS to initialRCS.

    Set stateFunction to ModeComputeApoapsisManeuverTransitionIn@.
    return.
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE COMPUTE APOAPSIS MANEUVER 																						////
//																														////
// Here we merely calculate the apoapsis maneuver necessary to put us into the target orbit. We create a maneuver 		////
// node for it, but we don't try to execute it or anything. MechJeb does a fine job of executing maneuver nodes.		////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

local function ModeComputeApoapsisManeuverTransitionIn {
    set modeName to "COMPUTE APOAPSIS MANEUVER".
    // missionLog("MODE to " + modeName).

    local v1 is SQRT( SHIP:BODY:MU * ( (2/(SHIP:BODY:RADIUS + ALT:APOAPSIS)) - (1/SHIP:ORBIT:SEMIMAJORAXIS) ) ).
    local v2 is SQRT( SHIP:BODY:MU * ( (2/(SHIP:BODY:RADIUS + ALT:APOAPSIS)) - (1/GetSMA(launchToApoapsis)) ) ).
    local Δv is v2 - v1.

    local apoapsisManeuver to NODE( TIME:SECONDS + ETA:APOAPSIS, 0.0, 0.0, Δv).
    ADD apoapsisManeuver.

    set stateFunction to ModeNullRatesTransitionIn@.
    return.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE NULL RATES 																										////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

local function ModeNullRatesTransitionIn {
    set modeName to "NULL RATES".
    // missionLog("MODE to " + modeName).

    set SHIP:CONTROL:NEUTRALIZE to TRUE.

	set controlThrottle to 0.0.
    killSteering().
	
    set stateFunction to ModeNullRatesLoopFunction@.
    return.
}

local function ModeNullRatesLoopFunction {
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

local function ModeEndProgramTransitionIn {
    set modeName to "END PROGRAM".
    // missionLog("MODE to " + modeName).
    
	set SHIP:CONTROL:NEUTRALIZE to TRUE.
	set SHIP:CONTROL:PILOTMAINTHROTTLE to 0.0.
    
	UNLOCK THROTTLE.
    UNLOCK STEERING.
	WAIT 1.
	
    set RCS to initialRCS.
	set SAS to initialSAS.

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

global function StartTimeWarp {
    if useTimeWarp AND KUNIVERSE:TIMEWARP:RATE <> 2.0 {
        set KUNIVERSE:TIMEWARP:MODE to "PHYSICS".
        set KUNIVERSE:TIMEWARP:RATE to 2.0.
    }
}

global function stopTimeWarp {
    KUNIVERSE:TIMEWARP:CANCELWARP().
}





////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// UTILITY FUNCTIONS                                                       											////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// hold current attitude
local function killSteering {
	set STEERING to "KILL".
}

// Can we jettison the launch shroud?
local function CheckForShroudJettison {

    // Trigger fairing jettison if we're past max. Q AND we're at the threshold dynamic pressure.
    if NOT launchShroudsAll:EMPTY AND SHIP:Q < flightState_MaxQ AND SHIP:Q < fairingJettisonQ {

		if launchShroud:HASMODULE("ModuleProceduralFairing") {
			launchShroud:GETMODULE("ModuleProceduralFairing"):DOEVENT("Deploy").
		}
		
		launchShroudsAll:CLEAR.
		set launchShroud to 0.
		
    }
	
	return.
}

// Can we start hot-staging stage 3?
local function CheckStageThreeHotStage {

	// figure out how much burn time is left in stage two
	// if it's 2 seconds or less, return true
	
	// the mass flow rate of a RD-108 in vaccuum is ~81.256 kg/s
	// thus 2 seconds of mass flow = 0.1625 tons of propellant
	// one ton of stock propellant is comprised of 90 units of LF + 110 units of OX
	// 90 x .1625 = 14.625 units of LF
	// 110 x .1625 = 17.875 units of OX
	
	local fuelRemaining is 0.0.
	
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
global function HeadingOfVector { 
	PARAMETER vecT.

	local east is VCRS(SHIP:UP:VECTOR, SHIP:NORTH:VECTOR).
	local trig_x is VDOT(SHIP:NORTH:VECTOR, vecT).
	local trig_y is VDOT(east, vecT).
	local result is ARCTAN2(trig_y, trig_x).

	if result < 0 { set result to 360 + result.} 
	
	return result.
}

// Wrapper for KUNIVERSE:TIMEWARP:WARPTO(timestamp).
global function WarpToLaunch
{
	PARAMETER newTS. // seconds since epoch
	
//	if newTS - TIME:SECONDS > 5 {
//		missionLog("Waiting for Launch Window to open").
//		
//		until WARPMODE = "RAILS" { 
//			set WARPMODE to "RAILS". 
//			set WARP to 1. 
//			wait 0.2. 
//		}
//	
//		missionLog("Warping to: " + TIME(newTS):FULL).
//		kuniverse:TimeWarp:WARPTO(newTS).
//
//	} ELSE {
//		missionLog("T-minus " + (TIME:SECONDS - newTS)).
//	
//	}
//	
//	return.

	RUNONCEPATH("../common/lib_warpControl.ks").
	LOCAL warpCon TO warp_control_init().

	WAIT UNTIL warpCon:execute(newTS - TIME:SECONDS).

	missionLog("Warped to: " + TIME:FULL).

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