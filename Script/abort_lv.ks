@LAZYGLOBAL OFF.
SET CONFIG:IPU TO 2000.0.

{	// this is a library of functions for managing abort modes for a heavy-lift rocket
	// it is modeled after NASA Saturn/Apollo mission abort modes
	
	// you really only need 2 modes, 
	// one for handling any abort that separates the SM from the rest of the spacecraft
	// and one to handle the contingency orbit insertion using the SIV-B booster 

	LOCAL abortLib IS Import("abort").
	LOCAL getCurrentMode IS abortLib:GET_CURRENT_MODE@.
	LOCAL setAbortMode IS abortLib:SET_ABORT_MODE@.

	LOCAL utilities IS Import("utility").
	LOCAL Do_Event IS utilities:DO_EVENT@.

	LOCAL allmodes IS LEXICON(
		"IA", run_IA@,
		"II", run_II@,
		"IV", run_IV@,
		"IVB", run_IVB@,
		"OBT", run_OBT@
	).

	// don't abort if you're already in an abort mode
	LOCAL abort_Lockout IS FALSE.

	// this is a bad day for everybody
	LOCAL FUNCTION RUN_IA {

		Range_Safety("RSO_A", 0.3).
		
		// shut off any running engines
		Killswitch_Engaged().
		
		// fire any available retrorockets
		Fire_Retros().

		// wave goodbye
		// shut down the CPU
		WAIT 0.
		CORE:DEACTIVATE().
	}

	// this is maybe more of a controlled disaster
	LOCAL FUNCTION RUN_II {

		// try to get stable so that the CSM can escape without issues
		RCS ON.
		LOCK STEERING TO LOOKDIRUP(SHIP:PROGRADE:VECTOR, SHIP:UP:VECTOR).
		
		// shut off any running engines
		Killswitch_Engaged().
		
		// blow the alligator
		LOCAL dec IS SHIP:PARTSTAGGED("LM_FAIRING")[0].
		dec:GETMODULE("ModuleProceduralFairing"):DOEVENT("Deploy").
		WAIT 3.	
	
		// trigger timer for range safety ordinance, if available
		Range_Safety("RSO_A", 60).
		
		// fire any available retrorockets
		Fire_Retros().

		// uncouple from the CSM
		LOCAL LV_DECOUPLER IS SHIP:PARTSTAGGED("LV_DECOUPLER")[0].
		LV_DECOUPLER:GETMODULE("ModuleDecouple"):DOEVENT("Decouple").
		WAIT 0.	

		SET SHIP:CONTROL:FORE TO -1.0.
		WAIT 10.
		SET SHIP:CONTROL:FORE TO 0.
		WAIT 1.

		// wave goodbye
		// shut down the CPU

		CORE:DEACTIVATE().	
	}

	// maybe the CSM will be able to make it to orbit without us
	LOCAL FUNCTION RUN_IV {
		RUN_II().
	}

	// maybe we can get to orbit with the SIV-B booster
	LOCAL FUNCTION RUN_IVB {

		PRINT "*** ABORT MODE IVB ***".
		
		// trigger timer for range safety ordinance, if available
		Range_Safety("RSO_B", 60).
		
		// shut off any running engines
		Killswitch_Engaged().
		WAIT 0.
		
		// fire any available retrorockets
		Fire_Retros().
		
		// decouple from SII booster
		IF Do_Event("S2_DECOUPLER", "ModuleDecouple", "Decouple", TRUE) WAIT 0.

		LOCK STEERING TO "KILL".
		LOCK THROTTLE TO 1.0.

		// fire ullage
		FOR en IN SHIP:PARTSTAGGED("S3_ULL") { en:ACTIVATE(). }
		
		// activate the J2
		WAIT 3.5.
		FOR en IN SHIP:PARTSTAGGED("S3_ENGINE") { en:ACTIVATE(). }

		// reboot and reload m_IVB mission files
		IF NOT EXISTS(MISSION_MODE) CREATE(MISSION_MODE).
		LOCAL h IS OPEN(MISSION_MODE).
		h:CLEAR().
		h:WRITE("export(""m_mode_ivb"").").
		
		// delete the current runmode because new mission
		DELETEPATH(RUNMODE).
		
		REBOOT.
		
	}		
	
	// you have made it to orbit
	// continue to hand-off the LM, etc.
	LOCAL FUNCTION RUN_OBT {
		// return to main program?
		
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
		"RUN_ABORT_MODE", RUN_ABORT_MODE@,
		"SET_ABORT_MODE", SET_ABORT_MODE@
	).
	
	Export(abortmode).
}