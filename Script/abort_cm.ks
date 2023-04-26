@LAZYGLOBAL OFF.
SET CONFIG:IPU TO 2000.0.

{	// this is a library of functions for managing abort modes for a command module
	// it is modeled after NASA Saturn/Apollo mission abort modes
	
	// you really only need 3 modes, 
	// one for handling any abort that separates the CM from the rest of the spacecraft
	// one for getting to orbit on the SIV-B
	// one for getting to orbit on the SM

	LOCAL abortLib IS Import("abort").
	LOCAL getCurrentMode IS abortLib:GET_CURRENT_MODE@.
	LOCAL setAbortMode IS abortLib:SET_ABORT_MODE@.

	LOCAL allmodes IS LEXICON(
		"IA", run_IA@,
		"II", run_II@,
		"IV", run_IV@,
		"IVB", run_IVB@,
		"OBT", run_OBT@
	).

	// don't abort if you're already in an abort mode
	LOCAL abort_Lockout IS FALSE.
	
	// utilize the LES pitch motor to ensure the CM makes it to a water landing
	// deploy canards to ensure retrograde orientation
	// you will not go to space today
	LOCAL FUNCTION run_IA {
		PRINT "*** ABORT MODE IA ***".
		
		// decouple from the SM
		LOCAL dec IS SHIP:PARTSTAGGED("SM_DECOUPLER")[0].
		dec:GETMODULE("ModuleDecouple"):DOEVENT("Decouple").

		// fire the LES
		LOCAL les IS SHIP:PARTSTAGGED("LES")[0].
		les:ACTIVATE.
		
		// jettison LES
		WAIT UNTIL les:FLAMEOUT.
		LOCAL dp IS SHIP:PARTSTAGGED("theCM_PORT")[0].
		dp:GETMODULE("ModuleDockingNode"):DOEVENT("Undock").		
		WAIT 0.

		RCS ON.
		LOCK STEERING TO SHIP:SRFRETROGRADE.
		
		WAIT UNTIL SHIP:VERTICALSPEED <= 0.
		STAGE.   // arm and/or deploy chutes
		
		UNLOCK STEERING.

		WAIT UNTIL SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED".
		
		CORE:DEACTIVATE().	
		// REBOOT?
	}
	
	// utilize the LES 
	// deploy canards to ensure retrograde orientation
	// you will not go to space today
	LOCAL FUNCTION RUN_IB {
		RUN_IA().
	}
	
	// utilize the LES
	// use CM RCS to ensure retrograde orientation and fly towards water
	// you will not get to orbit
	LOCAL FUNCTION RUN_IC {
		RUN_IA().
	}	

	// utilize the SM main engines to get away
	// CM separates and splashes immediately (emergency)
	// you will not get to orbit
	LOCAL FUNCTION RUN_II {
		PRINT "*** ABORT MODE II ***".
		
		UNTIL FALSE {
			// wait for the LV to decouple
			IF SHIP:PARTSTAGGED("theLM_PORT"):LENGTH = 0 {
								
				LOCK STEERING TO LOOKDIRUP(SHIP:PROGRADE:VECTOR, SHIP:UP:VECTOR).
				LOCK THROTTLE TO 1.0.
				
				RCS ON.
				SET SHIP:CONTROL:FORE TO 1.0.
				WAIT 6.

				SHIP:PARTSTAGGED("SM_E")[0]:ACTIVATE().
				WAIT UNTIL (SHIP:POSITION - VESSEL("Saturn"):POSITION):MAG > 1000.
				LOCK THROTTLE TO 0.
				SET SHIP:CONTROL:FORE TO 0.
				WAIT 3.
				
				// turn towards normal
				LOCAL normalVector IS VCRS((SHIP:POSITION - SHIP:BODY:POSITION):NORMALIZED, SHIP:PROGRADE:VECTOR):NORMALIZED.
				LOCK STEERING TO LOOKDIRUP(normalVector, SHIP:UP:VECTOR).
				WAIT 5.
				
				// open the drain valve
				LOCAL drnF IS SHIP:PARTSTAGGED("SM_DRAIN")[0].
				LOCAL drnR IS SHIP:PARTSTAGGED("SM_DRAIN")[1].
				drnF:GETMODULE("ModuleResourceDrain"):DoAction("drain", True).
				drnR:GETMODULE("ModuleResourceDrain"):DoAction("drain", True).
				WAIT 20.

				drnF:GETMODULE("ModuleResourceDrain"):DoAction("drain", FALSE).
				WAIT 3.
				
				// decouple the SM
				LOCAL dec IS SHIP:PARTSTAGGED("SM_DECOUPLER")[0].
				dec:GETMODULE("ModuleDecouple"):DOEVENT("Decouple").

				// let it get away
				WAIT 10.
				
				// face retro
				LOCK STEERING TO SHIP:SRFRETROGRADE.
				WAIT 10.
				UNLOCK STEERING.				

				WAIT UNTIL SHIP:VERTICALSPEED <= 0.
				STAGE.   // arm chutes

				WAIT UNTIL SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED".
		
				CORE:DEACTIVATE().	
				// REBOOT?
		
			}
		}
	}
	
	// utilize the SM main engines to get away
	// CM separates and splashes at predetermined site
	// you will not get to orbit
	LOCAL FUNCTION RUN_III {
		RUN_II().
	}
	
	// utilize the SM main engines to inject into orbit
	// you lost the Mun
	LOCAL FUNCTION RUN_IV {
		
		// write a mission mode file for Mode IV abort
		// reboot
		// by the time we come back online, the LV should have separated
		
		// for now hand it over to Jeb:
		PRINT "*** ABORT MODE IV ***".

		UNTIL done {
			// wait for the LV to decouple
			IF SHIP:PARTSTAGGED("theLM_PORT"):LENGTH = 0 {
								
				LOCK STEERING TO LOOKDIRUP(SHIP:PROGRADE:VECTOR, SHIP:UP:VECTOR).
				LOCK THROTTLE TO 1.0.
				
				RCS ON.
				SET SHIP:CONTROL:FORE TO 1.0.
				WAIT 6.

				SHIP:PARTSTAGGED("SM_E")[0]:ACTIVATE().
				WAIT UNTIL (SHIP:POSITION - VESSEL("Saturn"):POSITION):MAG > 1000.
				SET SHIP:CONTROL:FORE TO 0.
				RCS OFF.				
				
				PRINT "MC: Hey, Jeb, we think you can still get to orbit".
				WAIT 3.

				PRINT "Jeb: Roger that!".
				UNLOCK STEERING.
				UNLOCK THROTTLE.
				SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 1.
				SET SHIP:CONTROL:FORE TO 0.
				SET SHIP:CONTROL:TOP TO 0.
				SET SHIP:CONTROL:STARBOARD TO 0.
				WAIT 3.

				CORE:DEACTIVATE().
				// reboot?
			}
		}
	}		
	
	// stage S-II has failed, so 
	// utilize the S-IVB to get the spacecraft to a point where the 
	// SM main engine can achieve orbit
	// You lost the Mun
	LOCAL FUNCTION RUN_IVB {

		// write a mission mode file for Mode IVB abort
		// reboot
		// by the time we come back online, the LV should have sorted itself out		
		
		// for now just return to the main mission loop

	}		
	
	// you have made it to orbit, but can't continue your normal mission
	LOCAL FUNCTION RUN_OBT {
		
		PRINT "MC: congratulations, you made it to orbit".
		WAIT 3.
		PRINT "MC: sorry about the mun".
	}
	
	// somebody hit the big red button
	LOCAL FUNCTION RUN_ABORT_MODE {
		IF MISSION_ABORT AND NOT abort_Lockout {
		
			// make sure we have juice in the CM
			LOCAL cm IS SHIP:PARTSTAGGED("theCM")[0].
				FOR rs IN cm:RESOURCES {
					IF rs:NAME = "ELECTRICCHARGE" rs:ENABLED ON.
					IF rs:NAME = "MONOPROPELLANT" rs:ENABLED ON.
			}

			SET abort_Lockout TO TRUE.
			allmodes[getCurrentMode()]:CALL().
		}
		SET abort_Lockout TO MISSION_ABORT.
	}
	
	// figure out what mode we would use
	LOCAL FUNCTION SET_ABORT_MODE {
		IF MISSION_ABORT RETURN.
		setAbortMode().
	}	
				
	// export the "public" members
	LOCAL abortmode IS LEXICON(
		"SET_ABORT_MODE", SET_ABORT_MODE@,
		"RUN_ABORT_MODE", RUN_ABORT_MODE@
	).		
		
	Export(abortmode).
}