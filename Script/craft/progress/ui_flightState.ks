@LAZYGLOBAL OFF.

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  FLIGHT STATE                                                                                                        ////
//	show some fancy data on the screen
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

RUNONCEPATH("/common/lib_common.ks").
RUNONCEPATH("/common/lib_orbits.ks").
RUNONCEPATH("/common/lib_strings.ks").
RUNONCEPATH("guido.ks").

// keep track of time
LOCAL tPrevious IS TIME(0).
LOCAL Δt IS TIME(0).

LOCAL missionLogLineNumber IS 17.

// various blobs to show on the UI
GLOBAL modeName IS "INIT".

GLOBAL ui_DV_remains IS 0.
GLOBAL ui_DV_display IS "XXXX".
GLOBAL ui_BurnIn IS 0.
GLOBAL ui_BurnIn_Display IS "--- s".
GLOBAL ui_BurnTot IS 0.
GLOBAL ui_BurnTot_Display IS "--- s".

GLOBAL ui_Kss_RelIncline IS 0.
GLOBAL ui_Kss_PhaseAngle IS 0.
GLOBAL ui_Kss_ETA IS 0.
GLOBAL ui_Kss_Dist IS 0.
GLOBAL ui_Kss_ETA_display IS "----".
GLOBAL ui_Kss_Dist_display IS "XXXX.XXX".


// Run this once at program startup.
GLOBAL FUNCTION InitializeFlightState {
	// if there are any sensors we need to set up
	// if there are any calculations we need to initialize

	// this only needs to be updated at start and then after inclination burn?
	SET ui_Kss_RelIncline TO GetRelativeInclinationToKSS().

    RETURN.
}

GLOBAL FUNCTION InitializeScreen {
    CLEARSCREEN.
	
	SET TERMINAL:WIDTH TO 50.
	SET TERMINAL:HEIGHT TO 37.
	
	// things we might want to know:


	// current SHIP:STATUS
	// current mission functional mode
	
	// delta V available
	// delta V next node
	// time until burn
	// burn time (total) of next node

	// KSS phase angle
	// KSS relative inclination
	// KSS distance?
	
	// time to AN and DN?
	
	// KSS time to closest
	// KSS distance at closest
	// KSS relative velocity at closest
	
	// ???
	

//                   1         2         3         4         5
//         012345678901234567890123456789012345678901234567890
    PRINT "+-----------------------------------------------+ ". //  0
    PRINT "| T+00:00:00  SUB_ORBITAL           Mode_Circ_N | ". //  1
    PRINT "+-----------------------+-----------------------+ ". //  2
    PRINT "| THROTTLE     XXX %    | ORB APO   XXXX.XXX km | ". //  3
    PRINT "| RCS FWD      XXX %    | ORB PE    XXXX.XXX km | ". //  4
    PRINT "| RCS SBD      XXX %    | ORB INCL   XXX.XXX °  | ". //  5
    PRINT "| RCS TOP      XXX %    |                       | ". //  6
    PRINT "|                       | REL INCL   XXX.XXX °  | ". //  7
    PRINT "| Δv AVAIL    XXXX m/s  | PHASE      XXX.XXX °  | ". //  8
    PRINT "| Δv BURN     XXXX m/s  | ETA CA        ---- s  | ". //  9
    PRINT "|      IN       ---- s  | DIST CA   XXXX.XXX km | ". // 10
    PRINT "|     TOT        0.0 s  +-----------------------+ ". // 11
    PRINT "|                       |                       | ". // 12
    PRINT "|                       |                       | ". // 13
    PRINT "|                       |                       | ". // 14
    PRINT "|                       |                       | ". // 15
    PRINT "+-----------------------+-----------------------+ ". // 16
    PRINT "|                                               | ". // 17
    PRINT "|                                               | ". // 18
	PRINT "|                                               | ". // 19
	PRINT "|                                               | ". // 20
    PRINT "+-----------------------+-----------------------+ ". // 21
    PRINT "                                                  ". // 22

    RETURN.
}

// Update the flight state variables every time we go through the main loop.
GLOBAL FUNCTION UpdateFlightState {

	// we have a burn upcoming:
	IF ui_BurnIn > 0 {
		SET ui_DV_display TO RoundZero(ui_DV_remains).
		SET ui_BurnIn_Display TO "T-" + RoundZero(ui_BurnIn) + " s".
		SET ui_BurnTot_Display TO RoundZero(ui_BurnTot, 1) + " s".
	}

	// a burn is in progress
	IF ui_BurnIn <= 0 AND (THROTTLE >= 0.0 OR SHIP:CONTROL:FORE >= 0.0) {
		SET ui_BurnIn_Display TO "--- s".
		SET ui_BurnTot TO ui_BurnTot - Δt:SECONDS. // close enough for display
		SET ui_BurnTot_Display TO MIN(ui_BurnTot, 0.0).
		SET ui_BurnTot_Display TO RoundZero(ui_BurnTot, 1) + " s".
		SET ui_DV_display TO RoundZero(ui_DV_remains).
	}

	// the burn is complete and nothing further is scheduled
	IF ui_BurnIn <= 0.0 AND (THROTTLE = 0.0 AND SHIP:CONTROL:FORE = 0.0){
		SET ui_BurnIn_Display to "--- s".
		SET ui_BurnTot_Display TO "--- s".
		SET ui_DV_display TO "XXXX".
	}
	
	SET ui_Kss_PhaseAngle TO GetPhaseAngleToKSS().
		
	// pretty-print the closest approach
	IF ui_Kss_ETA > 0.0 SET ui_Kss_ETA_display TO "T-" + RoundZero(ui_Kss_ETA) + " s".
	IF ui_Kss_Dist > 0.0 SET ui_Kss_Dist_display TO RoundZero(ui_Kss_Dist / 1000.0, 3).
	
    RETURN.
}

// Update the console:
GLOBAL FUNCTION UpdateScreen {
    PRINT TIME(MISSIONTIME):CLOCK                              		AT (4,  1).		// Mission time, if started
 	PRINT SHIP:STATUS:PADLEFT(11)									AT (14, 1).		// SUB_ORBITAL or ORBITAL
	PRINT modeName:PADLEFT(20)                                      AT (27, 1).		// what mission mode are we in?

    PRINT RoundZero(THROTTLE * 100):PADLEFT(3)                      AT (15, 3).		// THROTTLE setting
	PRINT RoundZero(SHIP:CONTROL:FORE * 100):PADLEFT(4)             AT (14, 4).		// RCS output F/A
	PRINT RoundZero(SHIP:CONTROL:STARBOARD * 100):PADLEFT(4)        AT (14, 5).		// RCS output L/R
	PRINT RoundZero(SHIP:CONTROL:TOP * 100):PADLEFT(4)      		AT (14, 6).		// RCS output Z/N
 
    PRINT RoundZero(SHIP:APOAPSIS / 1000.0, 3):PADLEFT(8) 			AT (36, 3).		// current AP
    PRINT RoundZero(SHIP:PERIAPSIS / 1000.0, 3):PADLEFT(8)			AT (36, 4).		// current PE
 
    PRINT RoundZero(SHIP:DELTAV:CURRENT):PADLEFT(4)              	AT (14, 8).		// ship's dV
	PRINT ui_DV_display:PADLEFT(4)									AT (14, 9).		// burn dV
	PRINT ui_BurnIn_Display:PADLEFT(12)								AT (10, 10).	// burn ETA
	PRINT ui_BurnTot_Display:PADLEFT(12)							AT (10, 11).	// total burn time
 
    PRINT RoundZero(SHIP:OBT:INCLINATION, 3):PADLEFT(7)    			AT (37, 5).		// orbital inclination
	PRINT RoundZero(ui_Kss_RelIncline, 3):PADLEFT(7)    			AT (37, 7).		// relative inclination to KSS
	PRINT RoundZero(ui_Kss_PhaseAngle, 3):PADLEFT(7)				AT (37, 8).		// phase angle to KSS
 
 	PRINT ui_Kss_ETA_display:PADLEFT(7)								AT (36, 9).		// ETA to closest approach
	PRINT ui_Kss_Dist_display:PADLEFT(9)							AT (35, 10).	// distance at time of closest approach	

    RETURN.
}

GLOBAL FUNCTION missionLog {
    PARAMETER line.
	
	scrollMissionLog("T+" + TIME(MISSIONTIME):CLOCK + " " + line).
    RETURN.
}

LOCAL logTopLine IS 23.
LOCAL logBottomLine IS 35.
LOCAL logStack IS Stack().
LOCAL stackCopy IS Stack().

LOCAL FUNCTION scrollMissionLog {
	PARAMETER line.

	// push new line onto top of the stack
	logStack:PUSH(line).
	
	// get a local copy of the stack
	SET stackCopy TO logStack:COPY.	
	
	// pop stuff off the stack until the log is out of space
	FROM {local row is logTopLine.} UNTIL stackCopy:EMPTY OR row = logBottomLine + 1 STEP {set row to row + 1.} DO {
		LOCAL m IS stackCopy:POP().
		PRINT m:PADRIGHT(50) AT (0, row).
	}
	
	//WAIT 0.
	RETURN.
}

