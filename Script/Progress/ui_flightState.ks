@LAZYGLOBAL OFF.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  FLIGHT STATE                                                                                                       ////
//	show some fancy data on the screen
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

RUNONCEPATH("../common/lib_common.ks").
RUNONCEPATH("guido.ks").

// Debugging prints more messages to the screen.
local useDebugging is FALSE.

// keep track of time
local tPrevious is TIME(0).
local Δt is TIME(0).

// This is a proxy variable for SHIP:SENSORS:ACC. 
// By default, lock this variable to the zero vector.
lock accelerometerReading to V(0.0, 0.0, 0.0).

// The component of the vessel's proper acceleration in the forward direction.
// This is a scalar in m/s².
local flightState_α_long is 0.0.

// Maximum dynamic pressure experienced by the vehicle during ascent, in atmospheres.
global flightState_MaxQ is 0.0.

// An estimate of aerodynamic drag based on the difference between the expected acceleration (from total thrust and vehicle mass) 
// and the actual acceleration (measured by the on-board accelerometer). We compute this as a moving average to keep the vehicle 
// from getting into a throttle-control feedback loop. 
//
// FD_long = longitudinal component of drag acceleration in m/s².
//
local flightState_dragWindow is 5.
local flightState_dragData is QUEUE().
local flightState_FD_long is 0.0.

// ΣF = Total available thrust, in kilonewtons
local flightState_ΣF is 0.0.

// Δv calculations for efficiency, a rough measure of how well this AP works
local flightState_ΔvExpended is 0.0. 		// total Δv expended
local flightState_ΔvGained is 0.0. 		// Δv gained as orbital velocity
local flightState_ΔvEfficiency is 0.0.		// a ratio of Δv expended/gained

// TODO: move this to main program
global modeName is "".

// TODO: and this
// Keep track of which stage we're on.
global currentStage is  0.	// S1 = all boosters, S2 = Blok-A, S3 = Blok-I



// show the efficiency stats:
global calculateEfficiency is 0.0.


local missionLogLineNumber is 17.

global function InitializeScreen {
    if useDebugging {
        return.
    }

    CLEARSCREEN.
	calculateEfficiency OFF.

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
    print "+-----------------------X-----------------------+ ". // 10
    print "| CUR VEL    XX.XX m/s²                         | ". // 11
    print "| END VEL    XX.XX m/s²                         | ". // 12
	print "| AZ        XXX.XXX °                           | ". // 13
	print "| Pitch     XXX.XXX °                           | ". // 14
    print "+-----------------------+-----------------------+ ". // 15
    print "                                                  ". // 16

    return.
}

// Run this once at program startup.
global function InitializeFlightState {

    // Do we have an accelerometer part on board? 
    local allSensors is LIST().

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

// Update the flight state variables every time we go through the main loop.
global function UpdateFlightState {

    set Δt to TIME - tPrevious.
    set tPrevious to TIME.

    // Compute the vessel's current proper acceleration (α), then the component of α in the vehicle's forward direction (α_long).

    local flightState_α is accelerometerReading - (-1 * SHIP:UP:FOREVECTOR * (SHIP:BODY:MU / (SHIP:ALTITUDE + SHIP:BODY:RADIUS)^2)).
    set flightState_α_long to VDOT(flightState_α, SHIP:FACING:FOREVECTOR).

    // Compute a moving average of the estimated aerodynamic drag on the vehicle. 
	// We estimate the drag by calculating what our acceleration should be given current thrust vs. current mass and then taking 
	// the difference between the expected acceleration and the actual, measured acceleration. This is not 100% accurate because 
	// of engine gimbaling, but it's close enough.

    if SHIP:ALTITUDE <= 92000 { // 92000 is total atmo height for 2.5x RESCALE
        local αExpected is ((THROTTLE * flightState_ΣF) / SHIP:MASS) * SHIP:FACING:FOREVECTOR.
        local drag is αExpected - flightState_α.
        local drag_long is MIN(0.0, (-1) * VDOT(drag, SHIP:FACING:FOREVECTOR)).
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

	when controlAzimuth > 0.0 then { calculateEfficiency ON. }

	if calculateEfficiency {
		// Integrate total expended Δv, where Δv = Δv + ΣF × Δt.
		set flightState_ΔvExpended to flightState_ΔvExpended + ((THROTTLE * flightState_ΣF) / SHIP:MASS) * Δt:SECONDS.

		// Calculate Δv gained as orbital velocity in the direction of our launch azimuth. 
		set flightState_ΔvGained to (VDOT(SHIP:VELOCITY:ORBIT, HEADING(controlAzimuth, 0.0):FOREVECTOR)).

		// Calculate flight efficiency as a ratio of Δv gained to Δv expended.
		if flightState_ΔvExpended > 0 AND flightState_ΔvExpended > flightState_ΔvGained {
			set flightState_ΔvEfficiency to MIN(1.0, MAX(0.0, flightState_ΔvGained / flightState_ΔvExpended)).
		}
	}

    return.
}

// Update the console:
global function UpdateScreen {
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
    print RoundZero(getRelativeInclination(KSS), 3):PADLEFT(7)         AT (37,  5).

	if calculateEfficiency {
		print RoundZero(flightState_ΔvExpended):PADLEFT(4)              AT (39,  7).
		print RoundZero(flightState_ΔvGained):PADLEFT(4)                AT (39,  8).
		print RoundZero(flightState_ΔvEfficiency * 100):PADLEFT(3)      AT (40,  9).
	}

	print RoundZero(SHIP:VELOCITY:ORBIT:MAG, 2):PADLEFT(6)		AT (12,  11).
	print RoundZero(velAtAPO, 2):PADLEFT(6)         			AT (12,  12).
	print RoundZero(controlAzimuth, 3):PADLEFT(6)   			AT (11,  13).	
	print RoundZero(controlPitch, 3):PADLEFT(6)     			AT (11,  14).

    return.
}


global function missionLog {
    declare PARAMETER line.

    if useDebugging {
        print "T+" + TIME(MISSIONTIME):CLOCK + " " + line.
    } ELSE {
        print "T+" + TIME(MISSIONTIME):CLOCK + " " + line AT (0, missionLogLineNumber).
        set missionLogLineNumber to missionLogLineNumber + 1.
    }

    return.
}

global function missionDebug {
    declare PARAMETER line.

    if useDebugging {
        missionLog(line).
    }

    return.
}



