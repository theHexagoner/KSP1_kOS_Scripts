@LAZYGLOBAL OFF.
SET CONFIG:IPU TO 2000.0.

{	// this is a library of functions for managing further abort commands for the
	// Saturn S-IVB booster after entering MODE IVB during ascent
	
	LOCAL abortLib IS Import("abort").
	LOCAL GetCurrentMode IS abortLib:GET_CURRENT_MODE@.
	LOCAL SetAbortMode IS abortLib:SET_ABORT_MODE@.
	
	LOCAL utilities IS Import("utility").
	LOCAL Do_Event IS utilities:DO_EVENT@.

	LOCAL allmodes IS LEXICON(
		"IV", run_IV@,
		"IVB", run_IVB@,
		"OBT", run_OBT@
	).

	// don't abort if you're already in an abort mode
	LOCAL abort_Lockout IS FALSE.

	// maybe the CSM will be able to make it to orbit without us
	LOCAL FUNCTION RUN_IV {

		PRINT "*** ABORT MODE IVB ***".

		// try to get stable so that the CSM can escape without issues
		RCS ON.
		LOCK STEERING TO LOOKDIRUP(SHIP:PROGRADE:VECTOR, SHIP:UP:VECTOR).
		
		// shut off any running engines
		Killswitch_Engaged().
		
		// blow the gator
		IF Do_Event("LM_FAIRING", "ModuleProceduralFairing", "Deploy", TRUE) WAIT 3.
		
		// trigger timer for range safety ordinance, if available
		Range_Safety("RSO_A", 60).
		
		// fire any available retrorockets
		Fire_Retros().

		// uncouple from the CSM
		IF Do_Event("LV_DECOUPLER", "ModuleDecouple", "Decouple", TRUE) WAIT 0.
		
		SET SHIP:CONTROL:FORE TO -1.0.
		WAIT 10.
		SET SHIP:CONTROL:FORE TO 0.
		WAIT 0.

		// wave goodbye
		// shut down the CPU
		CORE:DEACTIVATE().	
	}

	// well, we tried... time to punt
	LOCAL FUNCTION RUN_IVB {
		RUN_IV().
	}		
	
	// you have made it to orbit and stuff goes wrong
	// decouple from the lander and deorbit
	LOCAL FUNCTION RUN_OBT {

		RCS ON.
		LOCK STEERING TO LOOKDIRUP(SHIP:PROGRADE:VECTOR, SHIP:UP:VECTOR).
		
		// shut off any running engines
		Killswitch_Engaged().
		
		// blow the gator
		IF Do_Event("LM_FAIRING", "ModuleProceduralFairing", "Deploy", TRUE) WAIT 3.

		// wait to get stable
		LOCAL stable IS False.
		LOCAL aligned IS TIME:SECONDS.
		
		UNTIL stable  {
			LOCAL ts IS TIME:SECONDS.
			LOCAL steerError IS ABS(STEERINGMANAGER:ANGLEERROR) +
								ABS(STEERINGMANAGER:ROLLERROR).

			IF steerError > 2 {
				SET aligned TO ts. // reset the timer
			}

			SET stable TO ts - aligned > 3. // have we been stable for 3 seconds?
			WAIT 0.
		}

		// uncouple from the CSM
		IF Do_Event("LV_DECOUPLER", "ModuleDecouple", "Decouple", TRUE) WAIT 0.

		// wave goodbye
		SET SHIP:CONTROL:FORE TO -0.1.
		WAIT 30.
		SET SHIP:CONTROL:FORE TO -1.
		WAIT UNTIL SHIP:OBT:PERIAPSIS < 10000.
		SET SHIP:CONTROL:FORE TO 0.
		WAIT 0.

		// shut down the CPU
		CORE:DEACTIVATE().	
	}

	// fire retros
	LOCAl FUNCTION Fire_Retros {
		LOCAL sepratrons IS SHIP:PARTSTAGGEDPATTERN("sep$").
		FOR sep IN sepratrons { sep:Activate(). }
	}

	// engines off
	LOCAL FUNCTION Killswitch_Engaged {
		FOR n IN SHIP:ENGINES { 
			IF n:IGNITION { 
				n:SHUTDOWN(). 
			}
		}
	}

	// trigger timer for range safety ordinance, if available
	LOCAL FUNCTION Range_Safety {
		PARAMETER partTag, 			// the tag of the part that has the self-destruct ordinance
				  delaySecs IS 10.	// get away fast!
	
		IF NOT SHIP:PARTSTAGGED(partTag):EMPTY AND
		   SHIP:PARTSTAGGED(partTag)[0]:HASMODULE("TacSelfDestruct") {
				PRINT "LV: Range safety initiated".
				LOCAL selfDestructModule TO SHIP:PARTSTAGGED(partTag)[0]:GETMODULE("TacSelfDestruct").
				selfDestructModule:SETFIELD("Time Delay", delaySecs).    		
				selfDestructModule:DOACTION("Self Destruct!", true).
		}	
	}
	
	// somebody hit the big red button
	LOCAL FUNCTION RUN_ABORT_MODE {
		IF MISSION_ABORT AND NOT abort_Lockout {
			SET abort_Lockout TO TRUE.
			allmodes[GetCurrentMode()]:CALL().		
		}
		SET abort_Lockout TO MISSION_ABORT.
	}

	// figure out what mode we would use
	LOCAL FUNCTION SET_ABORT_MODE {
		IF MISSION_ABORT RETURN.
		SetAbortMode().
	}

	// export the "public" members
	LOCAL abortmode IS LEXICON(
		"RUN_ABORT_MODE", RUN_ABORT_MODE@,
		"SET_ABORT_MODE", SET_ABORT_MODE@
	).
	
	Export(abortmode).
}