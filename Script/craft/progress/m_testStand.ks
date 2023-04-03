@LAZYGLOBAL OFF.

// this is a script for a Progress spacecraft to rendezvous with KSS
SET CONFIG:IPU TO 2000.0.

// Pause the game when the program ends. Useful for unattended launches.
LOCAL pauseGameWhenFinished is FALSE.

// If useTimeWarp is true, we'll use 2× physics warp during those ascent modes
// where it's safe. Ish. Use at your own risk.
LOCAL useTimeWarp is FALSE.

// our target:
GLOBAL KSS is VESSEL("The KSS").


PRINT "Initializing display logic...".
RUNONCEPATH("/common/lib_common.ks").
RUNONCEPATH("ui_flightState.ks").

LOCAL stateFunction IS {}.


// circularize enough to remain in orbit
LOCAL FUNCTION Mode_Circ_N {
	SET modeName TO "CIRCULARIZE".
    missionLog("CPU: Computing circularize burn").
    WAIT 3.

 	missionLog("CPU: Adding node to flight plan").
	missionLog("CPU: Calculating burn time").
	missionLog("CPU: Awaiting burn").

	SET stateFunction to Mode_Circ_Loop@.
	RETURN.	
}


// loop through main program until the circularization burn is complete
LOCAL FUNCTION Mode_Circ_Loop {
	
	missionLog("CPU: Locking steering to node").

	missionLog("CPU: Begin circularization burn").

	missionLog("CPU: Burn complete " + 0.03 + " dV remains").

	missionLog("CPU: Locking steering to prograde").
			
	SET stateFunction to Mode_Circ_O@.		
	
	RETURN.
}

// verify we are not going to burn up in the atmosphere
// figure out where to go next
LOCAL FUNCTION Mode_Circ_O {
	missionLog("Mode_Circ_O").
	missionLog("CPU: removing node from flight plan").

	SET stateFunction to Mode_Incline_N@.
	RETURN.
}

// if we are still not in orbital plane, plot inclination matching maneuver at the AN or DN
LOCAL FUNCTION Mode_Incline_N {
	SET modeName TO "INCLINATION".
    missionLog("CPU: Computing inclination burn").
    WAIT 3.
		
	missionLog("CPU: Adding node to flight plan").

	missionLog("CPU: Calculating burn time").

	missionLog("CPU: Awaiting burn").		
	
	SET stateFunction to Mode_Incline_Loop@.

	RETURN.
}

// make final correction with RCS
LOCAL FUNCTION Mode_Incline_Loop {

	IF TRUE {
		// execute the node
		missionLog("Executing plane change").
		SET stateFunction to Mode_Incline_O@.
		RETURN.
	}
	
	RETURN.
}

// not much to do here?
LOCAL FUNCTION Mode_Incline_O {
	missionLog("Mode_Incline_O").

	// IF we are not in active maneuver, rotate to sun-facing?
	//SET stateFunction to Mode_Trans_N@.

	// for now, end the program:
	SET stateFunction to Mode_Trans_N@.
	RETURN.
}

// after circularization and getting in plane, plot a hohmann transfer to the KSS
LOCAL FUNCTION Mode_Trans_N {
	missionLog("Mode_Trans_N").
	
	// how far in the future is the transfer maneuver?
	// consider reducing APO if it exceeds mission limits for duration?

	// plot hohmann intercept 
	
	SET stateFunction to Mode_Trans_Loop@.
	RETURN.
}

// execute hohmann
LOCAL FUNCTION Mode_Trans_Loop {
	
	IF TRUE {
		// execute the node
		missionLog("Executing Hohman transfer").
		SET stateFunction to Mode_Trans_O@.
	}
	
	RETURN.
}

// not much to do here?
LOCAL FUNCTION Mode_Trans_O {
	missionLog("Mode_Trans_O").

	// IF we are not in active maneuver, rotate to sun-facing?	
	SET stateFunction TO Mode_NullVee_N@.
	RETURN.
}

// arrive at KSS, null relative velocity w RCS
LOCAL FUNCTION Mode_NullVee_N {
	missionLog("Mode_NullVee_N").

	// do it
	SET stateFunction to Mode_NullVee_Loop@.
	RETURN.
}

// do it
LOCAL FUNCTION Mode_NullVee_Loop {
	
	IF TRUE {
		// do it
		missionLog("Nulling relative velocity with KSS.").
		SET stateFunction to Mode_NullVee_O@.
		RETURN.
	}
	
	RETURN.
}

// not much to do here?
LOCAL FUNCTION Mode_NullVee_O {
	missionLog("Mode_NullVee_O").
	
	// anything ELSE we need to do before transitioning to DOCKING program?

	SET stateFunction to Mode_NullRate_N@.
	RETURN.	
}

// null our rates before handing control back to PILOT
LOCAL FUNCTION Mode_NullRate_N {
	missionLog("Mode_NullRate_N").

	lock THROTTLE to 0.0.
    lock STEERING to "KILL".
	
    SET stateFunction to Mode_NullRate_Loop@.
    RETURN.
}

LOCAL FUNCTION Mode_NullRate_Loop {

    // How about NOT spinning out of control?
    IF SHIP:ANGULARVEL:MAG < 0.010 {
		MissionLog("Rates nulled").
        SET stateFunction to Mode_X_N@.
        RETURN.
    }

}

// end program, reboot?
LOCAL FUNCTION Mode_X_N {
    missionLog("Mode_X_N").
	
    SET stateFunction to {}.
    RETURN.
	
	
}


// Main program loop:

// start by making sure we are safely in orbit:
SET stateFunction to Mode_Circ_N@.

// init flight state:
InitializeFlightState().
InitializeScreen().

// run until the user quits it
UNTIL FALSE {

	UpdateFlightState().
	UpdateScreen().
	
	// enter the next pass through the state machine
	stateFunction:CALL().

    // Yield until the next physics tick.
    WAIT 0.

}













