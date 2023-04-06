@LAZYGLOBAL OFF.

// this is a script for a Progress spacecraft to rendezvous with KSS
SET CONFIG:IPU TO 2000.0.

// Pause the game when the program ends. Useful for unattended launches.
LOCAL pauseGameWhenFinished is FALSE.

// If useTimeWarp is true, we'll use 2× physics warp during those ascent modes
// where it's safe. Ish. Use at your own risk.
LOCAL useTimeWarp is FALSE.

// our target:
GLOBAL theKSS is VESSEL("The KSS").


PRINT "Initializing display logic...".
RUNONCEPATH("/common/lib_common.ks").
RUNONCEPATH("ui_flightState.ks").

LOCAL stateFunction IS {}.
CLEARSCREEN.

// run until the user quits it
UNTIL FALSE {

	UpdateFlightState().
	UpdateScreen().
	
	// enter the next pass through the state machine
	stateFunction:CALL().

    // Yield until the next physics tick.
    WAIT 0.

}













