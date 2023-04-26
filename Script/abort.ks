@LAZYGLOBAL OFF.
SET CONFIG:IPU TO 2000.0.

{	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	SATURN/APOLLO ABORT MODES
	//
	// 		MODE IA: (mode one alpha) from pre-launch until over water (MET 60s ish in 2.5x KSC)
	// 		This is the default mode, with the Apollo LES, it fires the "tiny" pitch rocket to impart additional pitch
	//
	// 		With the stock LES, we will treat all of these the same:
	// 		MODE IB: from end of IA until SHIP:ALTITUDE > 30.5km, does not fire the pitch rocket
	// 		MODE IC: from end of IB until LES is jettisoned, does not open the fairings
	//
	// 		MODE II: from LES jettison to point where you can't immediately deorbit and splash in the seas east of KSC
	// 		MODE III: from middle of stage 2 past the point where you can't deorbit immediately or else you can reach 
	//                planned splashdown zone
	//
	// 		MODE IVB: if we fail during stage two and are close enough or in space already
	// 	    MODE IV: from beginning of stage 3	

	// the various modes are roughly sequential and exclusive
	LOCAL allModes IS QUEUE().
		  allModes:PUSH("IA").
		  allModes:PUSH("II").
		  allModes:PUSH("IVB").
		  allModes:PUSH("IV").
		  allModes:PUSH("OBT").

	// the currently identified Abort Mode
	LOCAL currentMode IS LEXICON(
		"KEY", "IA"
	).

	LOCAL FUNCTION GET_CURRENT_MODE { RETURN currentMode:KEY. }

	// this method sets the Abort Mode
	LOCAL FUNCTION SET_ABORT_MODE {

		// as long as we have the LES, we remain in Mode IA
		LOCAL newMode IS currentMode:KEY.

		// is the current mode still valid?
		UNTIL newMode = allModes:PEEK() {
			SET newMode TO allModes:POP().
		}
		
		// evaluate the situation
		LOCAL isValid IS FALSE.
		
		IF newMode = "IA" {
			// if the LES is gone, go to Mode II
			IF SHIP:PARTSTAGGED("LES"):EMPTY {
				PRINT "Mode IA no longer valid".
				allModes:POP().						// remove IA
				SET newMode TO allModes:PEEK().     // set to II				
			} ELSE SET isValid TO TRUE.
		}

		IF NOT isValid AND newMode = "II" {
			// this mode is the only option up to 85km ASL
			// this mode requires a functioning Service Module
			
			IF SHIP:ALTITUDE > 85000 OR 
			   SHIP:PARTSTAGGED("SERVICE_MODULE"):EMPTY {
					PRINT "Mode II no longer valid".
					allModes:POP().						// remove II
					SET newMode TO allModes:PEEK().		// set to IVB
			} ELSE SET isValid TO TRUE.
		}
		
		IF NOT isValid AND newMode = "IVB" {
			// normal flight usually drops the S-II stage around 95km ASL
			// this mode is not relevant after we get into any kind of orbit
			// ths mode requires functioning S-IVB stage
			IF SHIP:ALTITUDE >= 95000 OR
   			   SHIP:STATUS = "ORBITING" OR 
			   SHIP:PARTSTAGGED("theLV"):EMPTY	{
					PRINT "Mode IVB no longer valid".
					allModes:POP().						// remove IVB
					SET newMode TO allModes:PEEK().		// set to IV
			} ELSE SET isValid TO TRUE.
		}
		
		IF NOT isValid AND newMode = "IV" {
			// UNTESTED: this mode starts becoming feasible around ???? ASL
			// this mode is not relevant after we get into any kind of orbit
			// ths mode requires functioning service module
			IF SHIP:ALTITUDE < 95000 OR 
			   SHIP:STATUS = "ORBITING" OR
			   SHIP:PARTSTAGGED("SERVICE_MODULE"):EMPTY {
					PRINT "Mode IV no longer valid".
					allModes:POP().						// remove IV
					SET newMode TO allModes:PEEK().		// set to OBT
			} ELSE SET isValid TO TRUE.
		}	

		IF NOT isValid AND newMode = "OBT" {
			// we must be in some kind of orbit:
			IF SHIP:STATUS = "ORBITING" {
				SET isValid TO TRUE.
			}
		}

		IF NOT isValid {
			PRINT "FAILED SET_ABORT_MODE".
			PRINT "FROM " + currentMode:KEY + " to " + newMode.
			PRINT "PRESS CTRL+C TO TERMINATE".
			UNTIL FALSE { WAIT 0. }
		}

		IF currentMode:KEY <> newMode {
			SET currentMode:KEY TO newMode.
			PRINT "Abort Mode changed to " + newMode.
		}
	}

	// export the "public" members
	LOCAL this IS LEXICON(
		"SET_ABORT_MODE", SET_ABORT_MODE@,
		"GET_CURRENT_MODE", GET_CURRENT_MODE@
	).

	Export(this).
}