@LAZYGLOBAL OFF.

// This is an ascent script to launch a Tantares Progress spacecraft to the KSS from Woomerang Launch Site.
// Mostly nothing goes on in here except monitor for status updates from the Soyuz lift vehicle and wait for it 
// to complete its ascent program.

// When we hit targeted Q, we will jettison the launch shroud.

// When the Soyuz lift vehicle tells us it has completed ascent, we will assume active control of the mission and 
// instruct the Soyuz to decouple and separate before rebooting into the Rendezvous program which will complete our
// orbit and put us on course to intercept and dock with the KSS.

// Pause the game when the program ends. Useful for unattended launches.
LOCAL pauseGameWhenFinished IS FALSE.

// our target:
GLOBAL KSS IS VESSEL("The KSS").
LOCAL TERMINATE IS FALSE.  // only end this program when we are ready

// get information about the Progress spacecraft
PRINT "Loading parts and modules...".
RUNONCEPATH("spacecraft.ks").


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//// INTERNAL FLIGHT VARIABLES                                                                                          ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// mark timestamp:seconds at various points in the ascent flight-plan
LOCAL markTimeS IS 0.0.

// Dynamic pressure, in atmospheres, at which to jettison the payload fairings.
// this is about 62km on Kerbin
LOCAL fairingJettisonQ IS  0.001.  

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 	STATE MACHINE                                                                                                         //
//                                                                                                                        //
// 	The heart of this program is a finite-state machine, which means at any given time, the program can be in ONE of      //
// 	several possible modes. Each mode has a transition-in function, an optional loop function and an optional transition  //
// 	-out function. 																											  //
//                                                                                                                        //
// 	The transition-in function is called once when the machine enters that mode;                                          //
// 	The loop function is called once every time through the main program loop;                                            //
// 	If there is a transition-out function, it's called once right before we change to another mode.                       //
//                                                                                                                        //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL stateFunction IS {}.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  MODE PRE-LAUNCH                                                          											  //
//  There aren't even any kerbals aboard to get bored or hungry!                                                          //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////





LOCAL FUNCTION Mode_Pre_N {
	LOCAL buffer IS LIST(TRUE, "PROGRESS: pre-launch checks complete.").
	
	// examine the ship and get all the parts and modules
	IF GetProgressSpacecraft() = FALSE {
		SET buffer TO LIST(False, "PROGRESS: pre-launch checks failed.").
		PRINT "CPU: Mission failure, spacecraft did not meet specs".
	}
	
	PRINT "CPU: Spacecraft systems are online.".
	
	// let the lift vehicle know what's going on.
	linkToLvCPU:SENDMESSAGE(buffer).
	
	// go back to waiting for messages
	SET stateFunction TO {}.
	RETURN.
}







////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  MODE JETTISON LOOP                                                         											  //
//  Can we jettison the launch shroud?                                                                                    //
//	This also gets called during an abort to immediately jettison the shroud, regardless of Q                             //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_Jet_Loop {
	PARAMETER ignoreQ IS FALSE.
	
    // Trigger fairing jettison IF we're past max. Q AND we're at the threshold dynamic pressure.
    IF NOT launchShroudsAll:EMPTY AND ( ignoreQ OR SHIP:Q < fairingJettisonQ ) {
		IF launchShroud:HASMODULE("ModuleProceduralFairing") {
			launchShroud:GETMODULE("ModuleProceduralFairing"):DOEVENT("Deploy").
		}
		launchShroudsAll:CLEAR.
		SET launchShroud TO 0.
		SET stateFunction TO {}.
		
		PRINT "CPU: Launch shroud jettisoned.".
    }

	RETURN.
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  MODE END PROGRAM 																									  //
//  We get this message when the Soyuz lift vehicle's ascent program has ended for any reason.                            //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Mode_X_N {

    IF pauseGameWhenFinished AND NOT ABORT {
        KUNIVERSE:PAUSE().
    }   
   
	// if we are in flight, we should just issue an ABORT command and try over
	IF SHIP:STATUS = "FLIGHT" {
		PRINT "CPU: Mission failed, did not achieve space.".
		ABORT ON.
	}
	
	// make sure we are ready to move on?
	
	// if we are suborbital, 
	IF SHIP:STATUS = "SUB_ORBITAL" {
		PRINT "CPU: Initiate Separation".
	
		// talk to the lift vehicle CPU and tell it to decouple and separate
		LOCAL isDecoupled IS FALSE.

		LOCAL buffer IS LIST(TRUE, "Mode_DnS_N").
		linkToLvCPU:SENDMESSAGE(buffer).

		SET markTimeS TO TIME:SECONDS + 10.

		WAIT UNTIL NOT CORE:MESSAGES:EMPTY OR TIME:SECONDS >= markTimeS + 10. 
		
		IF NOT CORE:MESSAGES:EMPTY {
			LOCAL packet IS CORE:MESSAGES:POP().
			LOCAL data IS packet:CONTENT.
			SET isDecoupled TO data[0].
			PRINT "AGC: " + data[0] + ": " + data[1].
		}
	
		IF isDecoupled {
			// we are ready to move on to active control of flight in rendezvous program
			SET stateFunction TO {}.
			PRINT "CPU: Separated from LV".

		} ELSE {
			// attempt to directly decouple from the rocket
			PRINT "CPU: Failsafe separation initiated.".
			RUNONCEPATH("2:/S3.ks").

			IF decouplerModuleStageThree:HASEVENT("DECOUPLE") {
				FOR s in sepratronsStageThree {
					s:ACTIVATE.
				}
				decouplerModuleStageThree:DOEVENT("Decouple").
				PRINT "CPU: Separating from LV".
			}
		}
		
		TFS().
		RETURN.
	}

	PRINT "UNRECOVERABLE ERROR".
	ABORT ON.
	
}

LOCAL FUNCTION TFS {

	IF ConfirmSeparation() {
		PRINT "CPU: Rebooting To Rendezvous".
		SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
		SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.0.
		UNLOCK THROTTLE.
		UNLOCK STEERING.
		SAS ON.
		RCS ON.		
		WAIT 3.
		TERMINATE ON.
		RETURN.
	} ELSE {
		PRINT "FAILED TO SEPARATE. INITIATE ABORT.".
		ABORT ON.
	}
}

LOCAL FUNCTION ConfirmSeparation {
	RETURN SHIP:PARTSTAGGED("LvCpu"):EMPTY.
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  ABORT                                                                  											      //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
ON ABORT {
	PRINT "ABORT COMMAND RECEIVED".

	// WAIT until the Soyuz lift vehicle has decoupled and separated

	LOCK THROTTLE TO 0.0.
	LOCK STEERING TO "KILL".

	// blow the fairings
	Mode_Jet_Loop(TRUE).
	
	// start draining propellant?
	
	// turn towards normal vector?

	
	RETURN.
}

PRINT "Waiting for Soyuz IU to come online...".

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  MAIN LOOP                                                              											      //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
until TERMINATE {

	LOCAL functionName IS "".

	// comms from the Soyuz IU will tell us what is going on and when to change state
	IF NOT CORE:MESSAGES:EMPTY { 
		SET functionName TO CORE:MESSAGES:POP():CONTENT.
		PRINT "AGC: set function " + functionName.
		
		IF functionName = "Mode_Pre_N" SET stateFunction TO Mode_Pre_N@.
		IF functionName = "Mode_Jet_Loop" SET stateFunction TO Mode_Jet_Loop@.
		IF functionName = "Mode_X_N" SET stateFunction TO Mode_X_N@.
	}
	
	// enter the next pass through the state machine
	stateFunction:CALL().

    // Yield until the next physics tick.
    wait 0.
}

// after S3 has separated, we need to reboot to run the rendezvous software
WAIT 10.
REBOOT.
