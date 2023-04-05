@LAZYGLOBAL OFF.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  FLIGHT STATE                                                                                                       ////
//	show some fancy data on the screen
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

RUNONCEPATH("/common/lib_common.ks").
RUNONCEPATH("/common/lib_strings.ks").

//RUNONCEPATH("guido.ks").

// keep track of time
LOCAL tPrevious IS TIME(0).
LOCAL Δt IS TIME(0).

// This IS a proxy variable for SHIP:SENSORS:ACC. 
// By default, lock this variable TO the zero vector.
lock accelerometerReading TO V(0.0, 0.0, 0.0).

// The component of the vessel's proper acceleration in the forward direction.
// This IS a scalar in m/s².
LOCAL flightState_α_long IS 0.0.

// Maximum dynamic pressure experienced by the vehicle during ascent, in atmospheres.
GLOBAL flightState_MaxQ IS 0.0.

// An estimate of aerodynamic drag based on the difference between the expected acceleration (from total thrust and vehicle mass) 
// and the actual acceleration (measured by the on-board accelerometer). We compute this as a moving average TO keep the vehicle 
// from getting into a throttle-control feedback loop. 
//
// FD_long = longitudinal component of drag acceleration in m/s².
//
LOCAL flightState_dragWindow IS 5.
LOCAL flightState_dragData IS QUEUE().
LOCAL flightState_FD_long IS 0.0.

// ΣF = Total available thrust, in kilonewtons
LOCAL flightState_ΣF IS 0.0.

// Δv calculations for efficiency, a rough measure of how well this AP works
LOCAL flightState_ΔvExpended IS 0.0. 		// total Δv expended
LOCAL flightState_ΔvGained IS 0.0. 		// Δv gained as orbital velocity
LOCAL flightState_ΔvEfficiency IS 0.0.		// a ratio of Δv expended/gained

// TODO: move this TO main program
GLOBAL modeName IS "".

// TODO: and this
// Keep track of which stage we're on.
GLOBAL currentStage IS  0.	// S1 = all boosters, S2 = Blok-A, S3 = Blok-I

// show the efficiency stats:
GLOBAL calculateEfficiency IS 0.0.

LOCAL missionLogLineNumber IS 17.

// show the error:
GLOBAL planeError IS 0.0.
GLOBAL corrAngle IS 0.0.

GLOBAL FUNCTION InitializeScreen {
    CLEARSCREEN.
	
	SET TERMINAL:WIDTH TO 50.
	SET TERMINAL:HEIGHT TO 37.
	
	calculateEfficiency OFF.

//                   1         2         3         4         5
//         012345678901234567890123456789012345678901234567890
    PRINT "+-----------------------------------------------+ ". //  0
    PRINT "| T+00:00:00                                    | ". //  1
    PRINT "+-----------------------+-----------------------+ ". //  2
    PRINT "| THROTTLE     XXX %    | CUR APO   XXXX.XXX km | ". //  3
    PRINT "| RCS FWD      XXX %    | ORB INCL   XXX.XXX °  | ". //  4
    PRINT "| α_long     XX.XX m/s² | REL INCL   XXX.XXX °  | ". //  5
    PRINT "| G           X.XX      +-----------------------+ ". //  6
    PRINT "| FD_long    XX.XX m/s² | Δv EXPENDED  XXXX m/s | ". //  7
    PRINT "| ΣF_t      XXXXXX kN   | Δv GAINED    XXXX m/s | ". //  8
    PRINT "| ΣF_l      XXXXXX kN   | EFFICIENCY    XXX %   | ". //  9
    PRINT "+-----------------------X-----------------------+ ". // 10
    PRINT "| CUR VEL    XX.XX m/s²                         | ". // 11
    PRINT "|                                               | ". // 12
	PRINT "| AZ        XXX.XXX °     PLANE ERR  XXX.XXX °  | ". // 13
	PRINT "| Pitch     XXX.XXX °                           | ". // 14
    PRINT "+-----------------------+-----------------------+ ". // 15
    PRINT "                                                  ". // 16

    RETURN.
}

// Run this once at program startup.
GLOBAL FUNCTION InitializeFlightState {

    // Do we have an accelerometer part on board? 
    LOCAL allSensors IS LIST().

    LIST SENSORS IN allSensors.
    for s in allSensors {
        IF s:HASSUFFIX("TYPE") AND s:TYPE = "ACC" {
            lock accelerometerReading TO SHIP:SENSORS:ACC.
            BREAK.
        }
    }

    // Push some zeros onto the drag average calculation queue. This makes it simple TO compute a moving average 
	// from time t = 0 without having that average go all crazy from noise in the first few fractions of a second.
    until flightState_dragData:LENGTH = flightState_dragWindow {
        flightState_dragData:PUSH(0.0).
    }

    RETURN.
}

// Update the flight state variables every time we go through the main loop.
GLOBAL FUNCTION UpdateFlightState {

    SET Δt TO TIME - tPrevious.
    SET tPrevious TO TIME.

    // Compute the vessel's current proper acceleration (α), then the component of α in the vehicle's forward direction (α_long).

    LOCAL flightState_α IS accelerometerReading - (-1 * SHIP:UP:FOREVECTOR * (SHIP:BODY:MU / (SHIP:ALTITUDE + SHIP:BODY:RADIUS)^2)).
    SET flightState_α_long TO VDOT(flightState_α, SHIP:FACING:FOREVECTOR).

    // Compute a moving average of the estimated aerodynamic drag on the vehicle. 
	// We estimate the drag by calculating what our acceleration should be given current thrust vs. current mass and then taking 
	// the difference between the expected acceleration and the actual, measured acceleration. This IS not 100% accurate because 
	// of engine gimbaling, but it's close enough.

    IF SHIP:ALTITUDE <= 92000 { // 92000 IS total atmo height for 2.5x RESCALE
        LOCAL αExpected IS ((THROTTLE * flightState_ΣF) / SHIP:MASS) * SHIP:FACING:FOREVECTOR.
        LOCAL drag IS αExpected - flightState_α.
        LOCAL drag_long IS MIN(0.0, (-1) * VDOT(drag, SHIP:FACING:FOREVECTOR)).
        flightState_dragData:PUSH(drag_long).
        SET flightState_FD_long TO flightState_FD_long + drag_long/flightState_dragWindow - flightState_dragData:POP()/flightState_dragWindow.
    } ELSE {
        SET flightState_FD_long TO 0.0.
    }

    // Keep track of the maximum dynamic pressure on the vehicle. When we've
    // passed the point of maximum dynamic pressure, we start looking for a
    // point where it's safe TO jettison the launch shroud.
    IF SHIP:Q > flightState_MaxQ {
        SET flightState_MaxQ TO SHIP:Q.
    }

	// The total available thrust is used to compute expended Δv.
    SET flightState_ΣF TO SHIP:AVAILABLETHRUST.

	when controlAzimuth > 0.0 then { calculateEfficiency ON. }

	IF calculateEfficiency {
		// Integrate total expended Δv, where Δv = Δv + ΣF × Δt.
		SET flightState_ΔvExpended TO flightState_ΔvExpended + ((THROTTLE * flightState_ΣF) / SHIP:MASS) * Δt:SECONDS.

		// Calculate Δv gained as orbital velocity in the direction of our launch azimuth. 
		SET flightState_ΔvGained TO (VDOT(SHIP:VELOCITY:ORBIT, HEADING(controlAzimuth, 0.0):FOREVECTOR)).

		// Calculate flight efficiency as a ratio of Δv gained TO Δv expended.
		IF flightState_ΔvExpended > 0 AND flightState_ΔvExpended > flightState_ΔvGained {
			SET flightState_ΔvEfficiency TO MIN(1.0, MAX(0.0, flightState_ΔvGained / flightState_ΔvExpended)).
		}
	}

    RETURN.
}

// Update the console:
GLOBAL FUNCTION UpdateScreen {
    
	IF MISSIONTIME > 0 {
        PRINT TIME(MISSIONTIME):CLOCK                               AT ( 4,  1).
    }
    
	PRINT ("S" + currentStage + ": " + modeName):PADLEFT(34)        AT (13,  1).

    PRINT RoundZero(THROTTLE * 100):PADLEFT(3)                      AT (15,  3).
    
	PRINT RoundZero(SHIP:CONTROL:FORE * 100):PADLEFT(3)             AT (15,  4).

    IF flightState_α_long < 99.99 {
        PRINT RoundZero(flightState_α_long, 2):PADLEFT(6)           AT (12,  5).
    } ELSE {
        PRINT "--.--":PADLEFT(6)                                    AT (12,  5).
    }
    
	IF flightState_α_long/CONSTANT:g0 < 9.99 {
        PRINT RoundZero(flightState_α_long/CONSTANT:g0, 2):PADLEFT(6) AT (12,  6).
    } ELSE {
        PRINT "-.--":PADLEFT(5)                                     AT (12,  6).
    }
    PRINT RoundZero(flightState_FD_long, 2):PADLEFT(6)              AT (12,  7).
    PRINT RoundZero(flightState_ΣF):PADLEFT(6)                    	AT (12,  8).
  
    PRINT RoundZero(SHIP:OBT:APOAPSIS / 1000.0, 3):PADLEFT(8)       AT (36,  3).
    PRINT RoundZero(SHIP:OBT:INCLINATION, 3):PADLEFT(8)    			AT (36,  4).
    PRINT RoundZero(getRelativeInclination(KSS), 3):PADLEFT(7)         AT (37,  5).

	IF calculateEfficiency {
		PRINT RoundZero(flightState_ΔvExpended):PADLEFT(4)              AT (39,  7).
		PRINT RoundZero(flightState_ΔvGained):PADLEFT(4)                AT (39,  8).
		PRINT RoundZero(flightState_ΔvEfficiency * 100):PADLEFT(3)      AT (40,  9).
	}

	PRINT RoundZero(SHIP:VELOCITY:ORBIT:MAG, 2):PADLEFT(7)		AT (11,  11).
		
	PRINT RoundZero(controlAzimuth, 3):PADLEFT(7)   			AT (12,  13).	
	PRINT RoundZero(controlPitch, 3):PADLEFT(7)     			AT (12,  14).

	PRINT RoundZero(planeError, 3):PADLEFT(8)    				AT (36,  13).

    RETURN.
}


GLOBAL FUNCTION missionLog {
    PARAMETER line,
			  t IS MISSIONTIME.
	
	scrollMissionLog("T+" + TIME(t):CLOCK + " " + line).
    RETURN.
}

LOCAL logTopLine IS 17.
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



