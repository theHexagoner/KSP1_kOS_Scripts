@LAZYGLOBAL OFF.

// this is an ascent guidance script to launch a Soyuz rocket with payload to the KSS from Woomerang

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// SCRIPT CONTROL VARIABLES                                                                                           ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Set this lower after we make the guidance algorithm run more efficiently
SET CONFIG:IPU TO 1000.0.

// Pause the game when the program ends. Useful FOR unattended launches.
LOCAL pauseGameWhenFinished IS FALSE.

// If useTimeWarp is true, we'll use 2× physics warp during those ascent modes where it's safe.
LOCAL useTimeWarp IS FALSE.

// prevent the ship from doing unexpected stuff when coming off autopilot
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.0.

// This is kind of a hack TO damp roll oscillations.
SET STEERINGMANAGER:ROLLTS TO 5.0.

// also, keep the craft from rolling around slowly after lauch:
SET STEERINGMANAGER:ROLLCONTROLANGLERANGE TO 180.

// our target:
GLOBAL KSS IS VESSEL("The KSS").

// load programs FOR geting vehicle and launchpad info
PRINT "Loading parts and modules...".
RUNONCEPATH("lift_vehicle.ks").
RUNONCEPATH("launchpad.ks").

// load the guidance program
PRINT "Starting guidance program...".
RUNONCEPATH("guido.ks").

// load the UI
PRINT "Initializing display logic...".
RUNONCEPATH("ui_flightState.ks").

WAIT 3.


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// INTERNAL FLIGHT VARIABLES                                                                                          ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////



// when to launch into orbital plane of KSS.
LOCAL launchWindowTS IS TIME(0). 

// when the script ends, put RCS back where we found it
LOCAL initialRCS IS RCS.

// when the script ends, put RCS back where we found it
LOCAL initialSAS IS SAS.

// This used TO control the vehicle's steering.
GLOBAL controlPitch IS 0.0. 		// ° above the horizon
GLOBAL controlThrottle IS 0.0.   	// 1.0 = full throttle
GLOBAL controlAzimuth IS 0.0. 		// ° compass heading

// start off with engines idle
LOCK THROTTLE TO 0.0.

// keep track of the current heading
LOCAL myHeading IS HEADING(0.0, 0.0).

// Track altitude at launch TO know when we have lifted off and cleared moorings.
LOCAL launchAlt IS 0.0. 

// mark timestamp:seconds at various points in the ascent flight-plan
LOCAL markTimeS IS 0.0.

// has Stage 3 started hot-staging?
LOCAL isStage3HotStaging IS FALSE.


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 	STATE MACHINE                                                                                                         //
//                                                                                                                        //
// 	The heart of this program IS a finite-state machine, which means at any given time, the program can be in ONE of      //
// 	several possible modes. Each mode has a transition-in FUNCTION, a loop FUNCTION and possibly a transition-out         //
// 	FUNCTION. 																											  //
//                                                                                                                        //
// 	The transition-in FUNCTION IS called once when the machine enters that mode;                                          //
// 	The loop FUNCTION IS called once every time through the main program loop.                                            //
// 	If there IS a transition-out FUNCTION, it's called once right before we change TO another mode.                       //
//                                                                                                                        //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL stateFunction IS {}.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  MODE CALCULATE WINDOW                                                                                                 //
// 	Find the next good launch window, and the launch azimuth                                                              //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_LW {
	
	IF NOT SHIP:STATUS = "PRELAUNCH" {
		missionLog("Ship must be on launchpad.").
		SET stateFunction TO Mode_X_N@.
		RETURN.	
	}
	
	SET modeName TO "Calculating Launch Window...".
	missionLog(modeName).

	LOCAL launchDetails IS calculateLaunchDetails().
	SET controlAzimuth TO launchDetails[0].	
	SET launchWindowTS TO launchDetails[1].

	missionLog("Launch TO: " + RoundZero(launchDetails[0], 2) + "°").
	missionLog("Launch at: " + launchWindowTS:FULL).	

	SET stateFunction TO Mode_Pre_N@.
	RETURN.

}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// MODE PRE-LAUNCH                                                          											////
//// Here IS where we initialize most of the mission parameters and fire off all the MLP parts FOR the pre-game show	////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL hasMLP IS FALSE.
LOCAL soundWarning IS FALSE.

LOCAL FUNCTION Mode_Pre_N {
    SET modeName TO "PRELAUNCH".
    missionLog("MODE TO " + modeName).
	
	missionLog("predicted phase: " + GetFuturePhaseAngle(launchWindowTS:SECONDS - TIME:SECONDS)).

	// examine the ship and get all the parts and modules
	IF GetSoyuzRocket() = FALSE {
		missionLog("FAIL: Active vessel did not meet specs.").
		SET stateFunction TO Mode_X_N@.
		RETURN.
	}

	// make sure we can talk TO the CPU in our payload, and that it's OK	
	linkToPayloadCPU:SENDMESSAGE("Mode_Pre_N").
	
	SET markTimeS TO TIME:SECONDS.
	
	WAIT UNTIL NOT CORE:MESSAGES:EMPTY OR TIME:SECONDS >= markTimeS + 5.
	LOCAL payloadNoGo IS CORE:MESSAGES:EMPTY.
	
	IF NOT CORE:MESSAGES:EMPTY {
		LOCAL packet IS CORE:MESSAGES:POP().
		LOCAL data IS packet:CONTENT.
		SET payloadNoGo TO NOT data[0].
		missionLog(data[1]).
	}

	IF payloadNoGo {
		SET stateFunction TO Mode_X_N@.
		RETURN.			
	}

	// ALL INIT COMPLETE?
	SET hasMLP TO NOT SHIP:PARTSTAGGED("PREGAME"):EMPTY.
	
	WHEN SHIP:SENSORS:LIGHT >= 0.75 THEN LIGHTS OFF.
	WHEN SHIP:SENSORS:LIGHT <= 0.85 THEN LIGHTS ON.
	
	IF GetSoyuzLaunchpad() {
		IF hasMLP {
			WarpToLaunch(launchWindowTS:SECONDS - 70). // @ T-minus 70s
			SET stateFunction TO Mode_Pre_Loop@.	
		} ELSE {
			WarpToLaunch(launchWindowTS:SECONDS - 5).
			SET stateFunction TO Mode_I_Loop@.		
		}
	}

    // Capture the height above the ground in prelaunch.
    SET launchAlt TO ALT:RADAR.
	
	RETURN.

}

// KICK OFF ALL THE MLP TOYZ!
LOCAL FUNCTION Mode_Pre_Loop {
	
	IF TIME:SECONDS >= launchWindowTS:SECONDS {
		SET stateFunction TO Mode_L_N@.
		RETURN.
	}
	
	// make sure we are at full main throttle
	IF TIME:SECONDS >= launchWindowTS:SECONDS - 5 {
		SET controlThrottle TO 1.0.
		lock THROTTLE TO controlThrottle.
		RETURN.
	}

	// when we hit T-MINUS 60, play the SIREN
	IF TIME:SECONDS >= launchWindowTS:SECONDS - 60 AND soundWarning {
		SET soundWarning TO FALSE.
		
		missionLog("predicted phase: " + GetFuturePhaseAngle(launchWindowTS:SECONDS - TIME:SECONDS)).
		
		IF warningSirenModule <> 0 AND 
		   warningSirenModule:HASEVENT(warningEventName) {
				warningSirenModule:DOEVENT(warningEventName).
		}
	}
	
	// when we hit T-minus 70, play the MLP toys
	IF TIME:SECONDS >= launchWindowTS:SECONDS - 70 {
		IF hasMLP {
			SET hasMLP TO FALSE.
			SET soundWarning TO TRUE.
			LOCAL p IS SHIP:PARTSTAGGED("PREGAME")[0].
			LOCAL m IS p:GETMODULE("ModuleRoboticController").
			m:DOACTION("Play Sequence", TRUE).
			RETURN.		
		}
	}

	RETURN.
}

// NO MLP, so just fire engines
LOCAL FUNCTION Mode_I_Loop {

	// this should give the engines time to spin up
	IF TIME:SECONDS >= launchWindowTS:SECONDS - 5 {
	
		// Don't try to maneuver
		killSteering().

		// make sure we are at full throttle
		SET controlThrottle TO 1.0.
		lock THROTTLE TO controlThrottle.

		// do stuff to light the engines
		FOR f IN enginesStageOneAll {
			f:ACTIVATE.
		}

		SET stateFunction TO Mode_L_N@.
		RETURN.

	}

	RETURN.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE LAUNCH                                                                                                        	////
// Here is where we will do some final checks that engines are running and making good thrust before launch				////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_L_N {
    SET modeName TO "LAUNCH".
    missionLog("MODE TO " + modeName).

    // Don't try to maneuver
    killSteering().

	// check out the status of the S1 engines:
    LOCAL enginesIgnited IS TRUE.
    FOR e IN enginesStageOneAll {
        IF e:IGNITION = FALSE {
			SET enginesIgnited TO FALSE.
			BREAK.
		}
    }

    IF NOT enginesIgnited {
		missionLog("S1 ENGINES NO GO!").
		LOCK THROTTLE TO 0.0.
		SET stateFunction TO Mode_X_N@.
        RETURN.
    }

    SET stateFunction TO Mode_L_Loop@.
    RETURN.

}

LOCAL FUNCTION Mode_L_Loop  {

	LOCAL desiredThrust IS 1140.0.

	IF TIME:SECONDS >= launchWindowTS:SECONDS {
		IF SHIP:AVAILABLETHRUST < desiredThrust {
			missionLog("ENGINES NOT ENOUGH GO! " + SHIP:AVAILABLETHRUST ).
			lock THROTTLE TO 0.0.
			SET stateFunction TO Mode_X_N@.
		} ELSE {
			SET stateFunction TO Mode_Lift_N@.
		}
	}
	
	RETURN.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE LIFTOFF                                                                                                         ////
// from S1 engines ignition TO the vehicle actually moving                                                              ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_Lift_N {
    SET modeName TO "LIFTOFF".
    missionLog("MODE TO " + modeName).
	
    killSteering().

	IF hasMLP {
		IF launchMLP() = FALSE {
			missionLog("FAIL: Did not launch").
			SET stateFunction TO Mode_X_N@.
			RETURN.		
		}
	} ELSE {
		FOR m in launchClampModules {
			m:DOEVENT(launchClampEventName).
		}
	}

    SET stateFunction TO Mode_Lift_Loop@.
    RETURN.
}

LOCAL FUNCTION Mode_Lift_Loop {
  
    // Wait until we've actually lifted off the pad.
    IF ALT:RADAR >= launchAlt {
        SET stateFunction TO Mode_Asc_N@.
		SET currentStage TO 1.
        RETURN.
    }

    RETURN.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE ASCENT PROGRAM                                                                                                  ////
// basically, this gets us from Liftoff TO clearing any moorings                                                        ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_Asc_N {
    SET modeName TO "ASCENT PROGRAM".
    missionLog("MODE TO " + modeName).

    killSteering().

    SET stateFunction TO Mode_Asc_Loop@.
    RETURN.
}

LOCAL FUNCTION Mode_Asc_Loop {

    // Wait until the spacecraft clears its own height.
    IF ALT:RADAR > launchAlt * 1.5 {
        SET stateFunction TO Mode_Roll_N@.
        RETURN.
    }

    RETURN.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE ROLL PROGRAM                                                                                                    ////
// Here we BEGIN rolling such that the vehicle's "up" points in the opposite direction of the launch azimuth. 			////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_Roll_N {
    SET modeName TO "ROLL PROGRAM".
    missionLog("MODE TO " + modeName).
   
	SET controlPitch TO 90.0.
	SET myHeading TO HEADING(controlAzimuth, controlPitch).
    lock STEERING TO myHeading.

    SET stateFunction TO Mode_Roll_Loop@.
    RETURN.
}

LOCAL FUNCTION Mode_Roll_Loop {

    IF SHIP:AIRSPEED > 50.0 {
        SET stateFunction TO Mode_Flight_N@.
        RETURN.
    }

    RETURN.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  MODE FLIGHT LOOP                                                                                                    ////
//  Flight is controlled by closed loop guidance program.  See Guido.ks          										////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_Flight_N {
    SET modeName TO "FLIGHT LOOP".
    missionLog("MODE TO " + modeName).

	// make sure we are at full throttle
    SET controlThrottle TO 1.0.	
	
	// start in open-loop guidance
	CLOSED_LOOP ON.

	UpdateGuido(SHIP:ALTITUDE).

	SET controlPitch TO GUIDO:PPROG.
	SET controlAzimuth TO GUIDO:AZIMUTH.
	
	SET myHeading TO HEADING(controlAzimuth, controlPitch).
	LOCK STEERING TO myHeading.

	IF currentStage = 2 
		linkToPayloadCPU:SENDMESSAGE("Mode_Jet_Loop").
	
    SET stateFunction TO Mode_Flight_Loop@.
    RETURN.
}

LOCAL FUNCTION Mode_Flight_Loop {

	// we should never get here, so go ahead and fail the mission
	IF SHIP:MAXTHRUST = 0 {
        SET stateFunction TO Mode_X_N@.
        RETURN.
    }

    // If ANY of the side-booster engines is out, shut down all the booster engines and jettison them. 
    IF currentStage = 1 AND NOT enginesStageOneBoosters:EMPTY {
        FOR e IN enginesStageOneBoosters {
            IF NOT e:IGNITION OR e:FLAMEOUT {
                SET stateFunction TO Mode_BSD_N@.
                RETURN.
            }
        }
    }

	// If Stage 2 is almost finished we need to fire Stage 3.
	IF currentStage = 2 AND NOT isStage3HotStaging { 
		IF Eval_S3_HotStage() { 
			SET isStage3HotStaging TO TRUE.
			SET stateFunction TO Mode_S3_N@.
			RETURN.
		}
	}

	// Blok-A "Core", aka "Stage 2" has shut down
    IF currentStage = 2 AND SHIP:MAXTHRUST = 0 {
        SET stateFunction TO Mode_2SD_N@.
        RETURN.
    }

	IF SHIP:APOAPSIS >= launchToApoapsis {
        SET stateFunction TO Mode_3SD_N@.
        RETURN.
    }
		
	UpdateGuido(SHIP:ALTITUDE).

	SET controlPitch TO GUIDO:PPROG.
	SET controlAzimuth TO GUIDO:AZIMUTH.
	SET myHeading TO HEADING(controlAzimuth, controlPitch).
	
    RETURN.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE BOOSTER SHUTDOWN                                                                                                ////
// The boosters have shut down and we need to jettison them. 			                                    			////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_BSD_N {
    SET modeName TO "BOOSTER SHUTDOWN".
    missionLog("MODE TO " + modeName).

    StopTimeWarp().
    killSteering().

    SET stateFunction TO Mode_BSD_Loop@.
    RETURN.
}

LOCAL FUNCTION Mode_BSD_Loop {
    
	// any logic/operations that need time to evolve would go here
	killSteering().

    SET stateFunction TO Mode_BSep_N@.
    RETURN.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE BOOSTER SEPARATION                                                                                              ////
// Korolev would be proud												                                    			////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_BSep_N {
    SET modeName TO "BOOSTER SEPARATION".
    missionLog("MODE TO " + modeName).

    SET markTimeS TO TIME:SECONDS.
    StopTimeWarp().

    killSteering().

    SET stateFunction TO Mode_BSep_Loop@.
    RETURN.
}

LOCAL FUNCTION Mode_BSep_Loop {

	// don't be hasty...WAIT half a second
    IF TIME:SECONDS - markTimeS >= 0.5 {
    
		// this will decouple the radial boosters
		FOR f IN decouplerModulesStageOneAll {
			f:DOEVENT("Decouple").
		}

		enginesStageOneBoosters:CLEAR().
		enginesStageOneAll:CLEAR().
		
		SET currentStage TO 2.
		SET stateFunction TO Mode_Flight_N@.
        RETURN.
    }

    RETURN.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE S3 IGNITION                                                                                                     ////
// The stage 3 engine hot-stages for two seconds prior to S2 cutoff to account for ullage								////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_S3_N {
    SET modeName TO "S3 IGNITION".
    missionLog("MODE TO " + modeName).

	killSteering().

	engineStageThree:ACTIVATE.
	SET markTimeS TO TIME:SECONDS.

    SET stateFunction TO Mode_S3_Loop@.
    RETURN.
}

LOCAL FUNCTION Mode_S3_Loop {
	
	IF engineStageThree:IGNITION OR 
		TIME:SECONDS >= markTimeS + 2 OR 
		engineStageTwo:FLAMEOUT {
	    SET stateFunction TO Mode_S3_O@.
	}

    RETURN.
}

LOCAL FUNCTION Mode_S3_O {

	IF NOT engineStageThree:IGNITION {
		missionLog("S3 Engine Failure!").
		SET stateFunction TO Mode_X_N@.
		RETURN.
	}

	SET stateFunction TO Mode_2SD_N@.
    RETURN.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  MODE S2 Shutdown                                                                                              		  //
//  The stage 2 engine has shut down so do some housekeeping before separating it                                         //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_2SD_N {
    SET modeName TO "S2 SHUTDOWN".
    missionLog("MODE TO " + modeName).

    StopTimeWarp().
	killSteering().
	
	SET markTimeS TO TIME:SECONDS.

    SET stateFunction TO Mode_2SD_Loop@.
    RETURN.
}

LOCAL FUNCTION Mode_2SD_Loop {
	
	IF TIME:SECONDS - markTimeS >= 2.0 OR engineStageTwo:FLAMEOUT {
		engineStageTwo:SHUTDOWN.
	    SET stateFunction TO Mode_2Sep_N@.
		RETURN.
	}

    RETURN.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE S2 Separation                                                                                          			  //
// Decouple stage 2 and let stage 3 continue on to space                                                                  //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_2Sep_N {
    SET modeName TO "S2 SEPARATION".
    missionLog("MODE TO " + modeName).
    
	SET stateFunction TO Mode_2Sep_Loop@.
    RETURN.
}

LOCAL FUNCTION Mode_2Sep_Loop {

	// hot stage, IF possible
	IF decouplerModuleStageTwo:HASEVENT("DECOUPLE") {
		decouplerModuleStageTwo:DOEVENT("Decouple").
		
		// stage 3 should already be running ~ 100% thrust
		SET currentStage TO 3.
	
		// at this point there are only a few possible paths:

		// we are not done pitching
		IF SHIP:APOAPSIS <= launchToApoapsis {
			SET stateFunction TO Mode_Flight_N@.
			RETURN.
		}

		IF SHIP:APOAPSIS >= launchToApoapsis  {
			SET stateFunction TO Mode_3SD_N@.
			RETURN.
		}
	}

	missionLog("WRONG TROUSERS GROMMIT!").
	ABORT ON.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  MODE S3 SHUTDOWN 																									  //
//  We have reached AP or S3 is out of fuel. Prepare to hand off control to the payload spacecraft.                       //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_3SD_N {
    SET modeName TO "S3 SHUTDOWN".
    missionLog("MODE TO " + modeName).

    StopTimeWarp().

    SET controlThrottle TO 0.0.
	killSteering().

    SET stateFunction TO Mode_NR_N@.
    RETURN.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE NULL RATES 																										////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_NR_N {
    SET modeName TO "NULL RATES".
    missionLog("MODE TO " + modeName).
	
	SET controlThrottle TO 0.0.
    killSteering().
	RCS ON.
	
    SET stateFunction TO Mode_NR_Loop@.
    RETURN.
}

LOCAL FUNCTION Mode_NR_Loop {
    // How about NOT spinning out of control?
    IF SHIP:ANGULARVEL:MAG < 0.010 {
        SET stateFunction TO Mode_X_N@.
		RCS OFF.
        RETURN.
    }
	
	RETURN.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE END PROGRAM 																									////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_X_N {
    SET modeName TO "END PROGRAM".
    missionLog("MODE TO " + modeName).
	
    IF pauseGameWhenFinished AND NOT ABORT {
        KUNIVERSE:PAUSE().
    }	
	
	SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
	SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.0.
	UNLOCK THROTTLE.
    UNLOCK STEERING.

	WAIT 1.
	
    SET RCS TO initialRCS.
	SET SAS TO initialSAS.

	// update the payload CPU	
	linkToPayloadCPU:SENDMESSAGE("Mode_X_N").

	SET markTimeS TO TIME:SECONDS.

	WAIT UNTIL NOT CORE:MESSAGES:EMPTY OR TIME:SECONDS >= markTimeS + 10.
	IF NOT CORE:MESSAGES:EMPTY {
		LOCAL packet IS CORE:MESSAGES:POP().
		LOCAL data IS packet:CONTENT.
		IF data[0] = TRUE {
			IF data[1] = "Mode_DnS_N" SET stateFunction TO Mode_DnS_N@.
		}
		RETURN.
	}

	IF SHIP:STATUS = "FLIGHT" ABORT ON.
    RETURN.
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MODE DECOUPLE & SEPARATE																								////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_DnS_N {
    SET modeName TO "DECOUPLE AND SEPARATE".
    missionLog("MODE TO " + modeName).

	StopTimeWarp().
	CLEARSCREEN.
	
	PRINT "Preparing to separate".
	
	// be sure throttle is fully closed
	LOCK THROTTLE TO 0.0.	
	
	// blow the decoupler and sepratrons 
	IF decouplerModuleStageThree:HASEVENT("DECOUPLE") {
		// let the payload CPU know how we are doing
		linkToPayloadCPU:SENDMESSAGE(LIST(TRUE, "Firing separation ordinance.")).
		
		PRINT "Decoupling".
		
		decouplerModuleStageThree:DOEVENT("Decouple").		
		RUNONCEPATH("S3.ks").
		
		IF GetS3Ordinance() {
		
			PRINT "Firing separation ordinance".
		
			FOR s in sepratronsStageThree {
				s:ACTIVATE.
			}		

			WAIT 5.
			
			PRINT "Ship Periapsis: " + SHIP:OBT:PERIAPSIS.
			
			IF SHIP:OBT:PERIAPSIS > 15000.0 {
		
				PRINT "Steering to retro".
				LOCK STEERING TO SHIP:RETROGRADE.
			
				WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR, SHIP:RETROGRADE:VECTOR) < 3.0.
				
				PRINT "Deorbit burn".
				LOCK THROTTLE TO 1.0.
			
				WAIT UNTIL SHIP:PERIAPSIS <= 0.0.
				LOCK THROTTLE TO 0.0.
		
				PRINT "Deorbit burn complete".

			
			} 
			
			PRINT "GOING OFFLINE".
			CORE:DEACTIVATE().
			
		}

	} ELSE {
		WAIT 150.
		ABORT ON.
		RETURN.
	}

	
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// TIMEWARP CONTROL                                                       											////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

GLOBAL FUNCTION StartTimeWarp {
    IF useTimeWarp AND KUNIVERSE:TIMEWARP:RATE <> 2.0 {
        SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
        SET KUNIVERSE:TIMEWARP:RATE TO 2.0.
    }
}

GLOBAL FUNCTION StopTimeWarp {
    KUNIVERSE:TIMEWARP:CANCELWARP().
}




////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// UTILITY FUNCTIONS                                                       											////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// hold current attitude
LOCAL FUNCTION killSteering {
	LOCK STEERING TO "KILL".
}

// Can we start hot-staging stage 3?
LOCAL FUNCTION Eval_S3_HotStage {

	// figure out how much burn time IS left in stage two
	// IF it's 2 seconds or less, RETURN true
	
	// the mass flow rate of a RD-108 in vaccuum IS ~81.256 kg/s
	// thus 2 seconds of mass flow = 0.1625 tons of propellant
	// one ton of stock propellant IS comprised of 90 units of LF + 110 units of OX
	// 90 x .1625 = 14.625 units of LF
	// 110 x .1625 = 17.875 units of OX
	
	LOCAL fuelRemaining IS 0.0.
	
	// get the remaining fuel content of stage 2 tanks
	FOR f IN tanksStageTwo {
		FOR r IN f:RESOURCES {
			IF r:NAME = "LIQUIDFUEL" {
				SET fuelRemaining TO fuelRemaining + r:AMOUNT.
				BREAK.
			}
		}
	}
	
	IF fuelRemaining <= 15.0 {
		RETURN TRUE.
	} ELSE {
		RETURN FALSE.
	}
}

// warp speed, Mr. Data
LOCAL FUNCTION WarpToLaunch
{
	PARAMETER newTS. // seconds since epoch

	RUNONCEPATH("/common/lib_warpControl.ks").
	LOCAL warpCon TO warp_control_init().
	WAIT UNTIL warpCon:execute(newTS - TIME:SECONDS).
}





////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//   ABORT                                                                  											  //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
ON ABORT {
    StopTimeWarp().
    missionLog("ABORT").	
	missionLog("Type of selfDestructModule IS: " +  selfDestructModule:TYPENAME).

	RUNONCEPATH("m_abort.ks").
	RETURN.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// MAIN LOOP                                                              											////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


// go and get a launch window
SET stateFunction TO Mode_LW@.

// SET up all the stuff we will track in the UI
InitializeFlightState().

// initialize the UI
InitializeScreen().

// but don't bother updating it until we actually do something
// TODO: just RETURN whether or not anything has changed inside UpdateFlightState() 
LOCAL showUpdate IS FALSE.

// run until the user quits it
until FALSE {

	// IF we've gone off, start updating the UI
	IF showUpdate = FALSE AND stateFunction = Mode_Lift_N@ {
		SET showUpdate TO TRUE.
	}

// TODO: just RETURN whether or not anything has changed inside UpdateFlightState() 
	IF showUpdate = TRUE {
		// update the current flight state FOR the UI
		UpdateFlightState().
		UpdateScreen().
	}    

    // comms from the payload CPU will tell us what is going on with it
	IF NOT CORE:MESSAGES:EMPTY SET stateFunction TO CORE:MESSAGES:POP.
	// TODO: IF something failed take appropriate action:
	
	// enter the next pass through the state machine
	stateFunction:CALL().

    // Yield until the next physics tick.
    WAIT 0.
}