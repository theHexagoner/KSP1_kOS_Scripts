@LAZYGLOBAL OFF.

// this is a script for a Progress spacecraft to rendezvous with KSS

// set this lower after we make this run more efficiently
SET CONFIG:IPU TO 1000.0.

// track the time at the last point when we let KSP have control

// Pause the game when the program ends. Useful for unattended launches.
LOCAL pauseGameWhenFinished IS FALSE.

// If useTimeWarp is true, we'll use 2× physics warp during those ascent modes
// where it's safe. Ish. Use at your own risk.
LOCAL useTimeWarp IS FALSE.

// our target:
GLOBAL theKSS IS VESSEL("The KSS").

PRINT "Loading libraries...".
RUNONCEPATH("guido.ks").

PRINT "Loading parts and modules...".
RUNONCEPATH("spacecraft.ks").

PRINT "Initializing display logic...".
RUNONCEPATH("ui_flightState.ks").

// when the script ends put stuff back where we found it
LOCAL initialRCS IS RCS.
LOCAL initialSAS IS SAS.

WAIT 3.

SAS OFF.
RCS OFF.

// This is kind of a hack to damp roll oscillations.
SET STEERINGMANAGER:ROLLTS to 5.0.

// also, keep the craft from rolling around slowly after lauch:
SET STEERINGMANAGER:ROLLCONTROLANGLERANGE TO 180.

// start off with engines idle
LOCK STEERING TO SHIP:PROGRADE.

LOCAL controlThrottle IS 0.0.
LOCK THROTTLE to controlThrottle.

// for RCS burns
LOCAL controlTrans_X IS 0.0.  
LOCAL controlTrans_Y IS 0.0.
LOCAL controlTrans_Z IS 0.0.

// make sure the engine is activated.
SHIP:ENGINES[0]:ACTIVATE.

// spread out
PANELS ON.
LOCAL antennaList IS SHIP:MODULESNAMED("ModuleDeployableAntenna").
FOR ant IN antennaList {
	if ant:HASEVENT("extend") ant:DOEVENT("extend"). 
}

LOCAL stateFunction IS {}.


// TODO: launch window should have brought us up at a time when we can just go ahead and plot a rendezvous
// check for available rendezvous node within a window before or somewhat after apoapsis

// for now, lets do this the old fashioned way

LOCAL mnv_Circ IS NODE(666,0,0,0).
LOCAL mnv_Circ_BT IS LEXICON("MEAN", 0.0, "TOTAL", 0.0).
LOCAL mnv_Circ_dv0 IS 0.0. // starting deltaV of node


// circularize enough to remain in orbit
LOCAL FUNCTION Mode_Circ_N {
	SET modeName TO "CIRCULARIZE".
    missionLog("CPU: Computing circularize burn").

	LOCAL desiredSMA TO SHIP:BODY:RADIUS + ALT:APOAPSIS.

    LOCAL v1 IS SQRT( SHIP:BODY:MU * ( ( 2 / (SHIP:BODY:RADIUS + ALT:APOAPSIS) ) - ( 1 / SHIP:ORBIT:SEMIMAJORAXIS ) ) ).
    LOCAL v2 IS SQRT( SHIP:BODY:MU * ( ( 2 / (SHIP:BODY:RADIUS + ALT:APOAPSIS) ) - ( 1 / desiredSMA ) ) ).
    LOCAL Δv IS v2 - v1.

    SET mnv_Circ to NODE(TIME:SECONDS + ETA:APOAPSIS, 0.0, 0.0, Δv).
    
	missionLog("CPU: Adding node to flight plan").
	ADD mnv_Circ.

	missionLog("CPU: Calculating burn time").
	
	SET mnv_Circ_dv0 TO mnv_Circ:DELTAV.
	SET mnv_Circ_BT TO GetBurntime(mnv_Circ_dv0:MAG).
	
	// display updates
	SET ui_DV_remains TO mnv_Circ_dv0:MAG.
	SET ui_BurnTot TO mnv_Circ_BT:TOTAL.
	SET ui_BurnIn TO mnv_Circ:ETA - mnv_Circ_BT:MEAN.

	missionLog("CPU: Awaiting burn").
	SET stateFunction to Mode_Circ_Loop@.
	RETURN.	
}

LOCAL lockedSteeringToNode IS FALSE.

// loop through main program until the circularization burn is complete
LOCAL FUNCTION Mode_Circ_Loop {
	
	// if we are "circularized", just move on:
	IF controlThrottle = 0.0 AND SHIP:PERIAPSIS > 92000.0 AND SHIP:ORBIT:ECCENTRICITY < 0.1 {
		missionLog("CPU WARNING: Already in a circular orbit").
		RETURN.
	}

	// wait until 10 seconds to go to lock onto vector
	IF lockedSteeringToNode = FALSE AND (mnv_Circ:ETA - mnv_Circ_BT:MEAN <= 10.0) {
		SET lockedSteeringToNode TO TRUE.
		RCS ON.
		missionLog("CPU: Locking steering to node").
		LOCK STEERING TO mnv_Circ:DELTAV.
		RETURN.
	}

	// execute the apoapsis maneuver when we get to correct time
	IF lockedSteeringToNode AND controlThrottle = 0.0 AND (mnv_Circ:ETA - mnv_Circ_BT:MEAN <= 0) {
		missionLog("CPU: Begin circularization burn").
		SET controlThrottle TO 1.0.
		RETURN.
	}

	// executing:
	IF lockedSteeringToNode AND controlThrottle = 1.0 {
		// complete:
		IF (VDOT(mnv_Circ_dv0, mnv_Circ:DELTAV) < 0.1) {
			missionLog("CPU: Burn complete " + RoundZero(mnv_Circ:DELTAV:MAG, 2) + " dV remains").
			SET controlThrottle TO 0.0.
			
			missionLog("CPU: Locking steering to prograde").
			LOCK STEERING TO SHIP:PROGRADE.
			
			SET stateFunction to Mode_Circ_O@.		
		}
		
		SET ui_DV_remains TO mnv_Circ:DELTAV:MAG.
		RETURN.
	}

	// we're just waiting, so update the UI
	SET ui_BurnIn TO mnv_Circ:ETA - mnv_Circ_BT:MEAN.
	
	RETURN.
}

// verify we are not going to burn up in the atmosphere
// figure out where to go next
LOCAL FUNCTION Mode_Circ_O {
	missionLog("Mode_Circ_O").

	IF SHIP:PERIAPSIS <= 92000.0 {
		SET stateFunction TO Mode_Circ_N@.
		RETURN.
	}
		
	// remove the node when we are done:	
	REMOVE mnv_Circ.
	missionLog("CPU: removing node from flight plan").
	SET lockedSteeringToNode TO FALSE.

	// only show this after we get circular
	SET ui_Kss_ETA TO GetETA_ClosestApproachToKss().
	SET ui_Kss_Dist TO GetDist_ClosestApproachToKss(ui_Kss_ETA).
		
	SET stateFunction to Mode_Incline_N@.
	RETURN.
}

LOCAL mnv_Incline IS NODE(666,0,0,0).
LOCAL mnv_Incline_BT IS LEXICON("MEAN", 0.0, "TOTAL", 0.0).
LOCAL mnv_Incline_dv0 IS 0.0. // starting deltaV of node

// if we are still not in orbital plane, plot inclination matching maneuver at the AN or DN
LOCAL FUNCTION Mode_Incline_N {
	SET modeName TO "INCLINATION".
    missionLog("CPU: Computing inclination burn").
    WAIT 3.
	
	// we should also check:
	// is next node coming before our closest approach?
	// is the closest approach outside an acceptable threshold for docking?
	
	If GetRelativeInclinationToKSS() > 0.1 {
	
		// create a mnv for matching inclination
		SET mnv_Incline TO GetInclinationNode().
		
		missionLog("CPU: Adding node to flight plan").
		ADD mnv_Incline.

		missionLog("CPU: Calculating burn time").
		SET mnv_Incline_dv0 TO mnv_Incline:DELTAV.
		
		LOCAL rcsThrust IS MIN(2.0, mnv_Incline_dv0:MAG / 4.0).
		
		PRINT rcsThrust AT (4, 14).
		
		SET mnv_Incline_BT TO GetBurntime(mnv_Incline:NORMAL, rcsThrust, 260.0).
	
		// display updates
		SET ui_DV_remains TO mnv_Incline_dv0:MAG.
		SET ui_BurnTot TO mnv_Incline_BT:TOTAL.
		SET ui_BurnIn TO mnv_Incline:ETA - mnv_Incline_BT:MEAN.

		// then wait for time to execute it
		missionLog("CPU: Awaiting burn").		
	
		// make sure we are locked prograde, with Kerbin "down"
		LOCK STEERING TO LOOKDIRUP(SHIP:PROGRADE:VECTOR, -SHIP:BODY:POSITION).
	
		SET stateFunction to Mode_Incline_Loop@.
		RETURN.
	}

	SET stateFunction TO Mode_Incline_O@.
	RETURN.
}

// make final correction with RCS
LOCAL FUNCTION Mode_Incline_Loop {

		// execute the node when it's time
		// allow for some fluff because we are going to trail off the throttle
		IF controlTrans_X = 0.0 AND (mnv_Incline:ETA - mnv_Incline_BT:MEAN <= 1.0) {

			missionLog("CPU: Begin inclination burn").

			SET controlTrans_X TO MIN (1.0, 1.0 * (ABS(mnv_Incline:NORMAL) / 4.0)).
			IF controlTrans_X < 0.05 SET controlTrans_X TO 0.05.
			IF mnv_Incline:NORMAL > 0.0 SET controlTrans_X TO -controlTrans_X.
			
			SET SHIP:CONTROL:STARBOARD TO controlTrans_X.
			
			RETURN.
		}
		
		// executing:
		IF ABS(controlTrans_X) > 0.0 {
			
			// reduce thrust as we close in on target
			SET controlTrans_X TO MIN (1.0, 1.0 * (ABS(mnv_Incline:NORMAL) / 4.0)).
			IF controlTrans_X < 0.05 SET controlTrans_X TO 0.05.
			IF mnv_Incline:NORMAL > 0.0 SET controlTrans_X TO -controlTrans_X.
		
			// finished:
			IF mnv_Incline:DELTAV:MAG < 0.0 {
				missionLog("CPU: Burn complete " + RoundZero(mnv_Incline:DELTAV:MAG, 2) + " dV remains").
				SET controlTrans_X TO 0.0.
				
				missionLog("CPU: Locking steering to prograde").
				LOCK STEERING TO SHIP:PROGRADE.
				
				SET stateFunction to Mode_Incline_O@.	
			}

			RETURN.
		}

		// we're just waiting, so update the UI
		SET ui_BurnIn TO mnv_Circ:ETA - mnv_Circ_BT:MEAN.
		RETURN.


}

// not much to do here?
LOCAL FUNCTION Mode_Incline_O {

	// IF we are not in active maneuver, rotate to sun-facing?
		
	SET stateFunction to Mode_Trans_N@.
	RETURN.
}



// node for the Hohmann transfer:
LOCAL mnv_Transfer IS NODE(666,0,0,0).
LOCAL mnv_Transfer_BT IS LEXICON("MEAN", 0.0, "TOTAL", 0.0).
LOCAL mnv_Transfer_dv0 IS 0.0. // starting deltaV of node

// after circularization and getting in plane, plot a hohmann transfer to the KSS
LOCAL FUNCTION Mode_Trans_N {
	SET modeName TO "TRANSFER".
    missionLog("CPU: Computing transfer burn").
    WAIT 3.

	// plot hohmann intercept 
	
	// 1. Calculate the AP and PE of the transfer orbit. 
	//    Assume the PE is my current semi-major axis of SHIP the AP is the semi-major axis of the KSS.
	LOCAL transferOrbitSMA IS (SHIP:OBT:SEMIMAJORAXIS + theKSS:OBT:SEMIMAJORAXIS) / 2.

	// 2. Calculate the transfer time. This is done by calculating the period of my transfer orbit and dividing by 2. 
	//    The period of an orbit can be calculated using this formula:  2 * pi * SQRT(semiMajorAxis^3 / Mu)
	LOCAL transferTime IS CONSTANT:PI * SQRT(transferOrbitSMA^3 / BODY:MU).

	// 3. Calculate how many degrees per second the target object will move. 
	//    This is done by dividing 360 by the period of the target.
	LOCAL targetDPS IS 360 / theKSS:OBT:PERIOD.
	
	// 4: Calculate from results of steps 2 and 3 how far the target will move in the time it takes for the transfer:
	LOCAL targetTransferTravel IS targetDPS * transferTime.
	
	// 5: Calculate the phase angle for the transfer.
	//    This is the phase angle we must have between the SHIP and the KSS when we start the transfer burn.
	LOCAL transferPhaseAngle IS 180 - targetTransferTravel.

	// 6: Calculate how many degrees per second the SHIP is moving:
	LOCAL shipDPS IS 360 / SHIP:OBT:PERIOD.

	// 7: Measure the phase angle to the target.
	LOCAL currentPhaseAngle IS GetPhaseAngleToKSS().

	// 8: Calculate the ETA for the transfer burn
	LOCAL relativeDPS IS shipDPS - targetDPS.
	LOCAL diffPhaseAngle IS currentPhaseAngle - transferPhaseAngle.
	LOCAL burnETA IS diffPhaseAngle / relativeDPS.

	// 9: Calculate the DV needed for the transfer burn.
	LOCAL r1 IS (SHIP:OBT:SEMIMAJORAXIS + SHIP:OBT:SEMIMINORAXIS) / 2.
	LOCAL r2 IS (theKSS:OBT:SEMIMAJORAXIS + theKSS:OBT:SEMIMINORAXIS) / 2.
	LOCAL transferD IS SQRT(BODY:MU / r1) * (SQRT( (2 * r2) / (r1 + r2) ) - 1).

	// 10. Place the maneuver node using the calculated time (8) and dV (9)
	SET mnv_Transfer TO NODE(TIME + burnETA, 0.0, 0.0, transferD).
	ADD mnv_Transfer.

	missionLog("CPU: Adding node to flight plan").
	missionLog("CPU: Calculating burn time").

	SET mnv_Transfer_dv0 TO mnv_Transfer:DELTAV.
	SET mnv_Transfer_BT TO GetBurntime(mnv_Transfer_dv0:MAG).

	// display updates
	SET ui_DV_remains TO mnv_Transfer_dv0:MAG.
	SET ui_BurnTot TO mnv_Transfer_BT:TOTAL.
	SET ui_BurnIn TO mnv_Transfer:ETA - mnv_Transfer_BT:MEAN.

	// this would be the result of a perfect, instant transfer burn?
	SET ui_Kss_ETA TO TIME:SECONDS + mnv_Transfer:ETA + (theKSS:OBT:PERIOD / 2).

	// then wait for time to execute it
	missionLog("CPU: Awaiting burn").		
	
	// make sure we are locked prograde
	LOCK STEERING TO SHIP:PROGRADE.

	SET stateFunction to Mode_Trans_Loop@.
	RETURN.
}

LOCAL ts_TransferBurn IS TIME(0). // UT for transfer burn, seconds since epoch

// execute hohmann
LOCAL FUNCTION Mode_Trans_Loop {

	// when we get close make sure we are locked onto the node:
	IF NOT lockedSteeringToNode AND mnv_Transfer:ETA - mnv_Transfer_BT:MEAN <= 10 {
		LOCK STEERING TO mnv_Transfer:DELTAV.
		missionLog("CPU: Locking steering to node").
		SET lockedSteeringToNode TO TRUE.
	}

	// execute the node when it's time:
	IF lockedSteeringToNode AND controlThrottle = 0.0 AND mnv_Transfer:ETA - mnv_Transfer_BT:MEAN <= 0 {
		missionLog("CPU: Begin transfer burn").
		SET ts_TransferBurn TO TIME:SECONDS.
		SET controlThrottle TO 1.0.
		RETURN.		
	}

	// executing:
	IF lockedSteeringToNode AND controlThrottle = 1.0 {
	
		// complete:
		IF (VDOT(mnv_Transfer_dv0, mnv_Transfer:DELTAV) < 0.1) {
			missionLog("CPU: Burn complete " + RoundZero(mnv_Transfer:DELTAV:MAG, 2) + " dV remains").
			SET controlThrottle TO 0.0.
			
			missionLog("CPU: Locking steering to prograde").
			LOCK STEERING TO SHIP:PROGRADE.
			
			SET stateFunction to Mode_Trans_O@.		
		}
		
		// still burning:
		SET ui_DV_remains TO mnv_Transfer:DELTAV:MAG.
		RETURN.
	}

	// else just wait:
	SET ui_BurnIn TO mnv_Transfer:ETA - mnv_Transfer_BT:MEAN.
	RETURN.
}

// not much to do here?
LOCAL FUNCTION Mode_Trans_O {
	missionLog("Mode_Trans_O").
	
	// go ahead and calculate time until closest, distance at closest?
	LOCAL idealT IS ts_TransferBurn + (theKSS:OBT:PERIOD / 2).
	
	// poke around 3 minutes on either side
	SET ui_Kss_ETA TO GetETA_ClosestApproachToKss(idealT - 180, idealT + 180).
	SET ui_Kss_Dist TO GetDist_ClosestApproachToKss(ui_Kss_ETA).
		
	// if we are not in active maneuver, rotate to sun-facing?	

	// Time warp until we are within 2km of the KSS?

	SET stateFunction TO Mode_NullVee_N@.
	RETURN.
}



// node for the rendezvous burn:
LOCAL mnv_Rend IS NODE(666,0,0,0).

// arrive at KSS, null relative velocity w RCS
LOCAL FUNCTION Mode_NullVee_N {
	missionLog("Mode_NullVee_N").

	//assume we are within ~2km of the KSS

	// calculate a node to null relative velocity with the KSS
	// this is not exact, but it will be close 'nuff
	LOCAL dV IS SHIP:VELOCITY:ORBIT - theKSS:VELOCITY:ORBIT.
	
	// is this any more precise?
	LOCAL t IS TIME:SECONDS + 30.
	LOCAL vShip IS VELOCITYAT(SHIP, t):ORBIT.
	LOCAL vKss IS VELOCITYAT(theKSS, t):ORBIT.
	LOCAL pShip IS POSITIONAT(SHIP, t) - BODY:POSITION.
	LOCAL rampDv IS vKss - Vship.
	
	missionLog("rampDV: " + RoundZero(rampDv:MAG, 3) + " dV: " + RoundZero(dV:MAG, 3)).
	
	// project dv onto the radial/normal/prograde direction vectors to convert it from (X, Y, Z) into burn parameters
	// Estimate orbital directions by looking at position and velocity of SHIP
	LOCAL rv IS SHIP:POSITION:NORMALIZED.
	LOCAL vel IS SHIP:VELOCITY:ORBIT:NORMALIZED.
	LOCAL nv IS VCRS(rv, vel):NORMALIZED.
	LOCAL sr IS VDOT(dv, rv).
	LOCAL sn IS VDOT(dv, nv).
	LOCAL sp IS VDOT(dv, vel).
	
	// create a node for 30 seconds from now:
	SET mnv_Rend TO NODE(t, sr, sn, sp).
	ADD mnv_Rend.
	
	missionLog("CPU: Adding node to flight plan").

	// display updates
	SET ui_BurnIn TO mnv_Rend:ETA.	

	// make sure we are locked prograde, with Kerbin "down"
	LOCK STEERING TO LOOKDIRUP(SHIP:PROGRADE:VECTOR, -SHIP:BODY:POSITION).

	// then wait for time to execute it
	missionLog("CPU: Awaiting burn").		

	SET stateFunction to Mode_NullVee_Loop@.
	RETURN.
}

LOCAL FUNCTION Mode_NullVee_Loop {
	
	
	// execute the node when it's time:
	IF controlTrans_X = 0.0 AND 
	   controlTrans_Y = 0.0 AND
	   controlTrans_Z = 0.0 AND
	   mnv_Rend:ETA {
		
		missionLog("CPU: Begin rendezvous burn").
	    
		// is there any normal component to the burn?
		IF ABS(mnv_Rend:NORMAL) > 0.0 {
			SET controlTrans_X TO MIN (1.0, 1.0 * (ABS(mnv_Rend:NORMAL) / 4.0)).
			IF controlTrans_X < 0.05 SET controlTrans_X TO 0.05.
			IF mnv_Rend:NORMAL > 0.0 SET controlTrans_X TO -controlTrans_X.  // for some reason, backwards?
			
			SET SHIP:CONTROL:STARBOARD TO controlTrans_X.		
		}

		// is there any radial component to the burn?
		IF ABS(mnv_Rend:RADIALOUT) > 0.0 {
			SET controlTrans_Y TO MIN (1.0, 1.0 * (ABS(mnv_Rend:RADIALOUT) / 4.0)).
			IF controlTrans_Y < 0.05 SET controlTrans_Y TO 0.05.
			IF mnv_Rend:RADIALOUT > 0.0 SET controlTrans_Y TO -controlTrans_Y.  // for some reason, backwards?
			
			SET SHIP:CONTROL:TOP TO controlTrans_Y.		
		}

		// is there any prograde component to the burn?
		IF ABS(mnv_Rend:PROGRADE) > 0.0 {
			SET controlTrans_Z TO MIN (1.0, 1.0 * (ABS(mnv_Rend:PROGRADE) / 4.0)).
			IF controlTrans_Z < 0.05 SET controlTrans_Z TO 0.05.
			IF mnv_Rend:PROGRADE > 0.0 SET controlTrans_Z TO -controlTrans_Z.  // for some reason, backwards?
			
			SET SHIP:CONTROL:FORE TO controlTrans_Z.		
		}	
			
		RETURN.
	}

	// executing:
	IF ABS(controlTrans_X) > 0.0 OR
	   ABS(controlTrans_Y) > 0.0 OR
	   ABS(controlTrans_Z) > 0.0 {

			IF ABS(controlTrans_X) > 0.0 {
				// reduce thrust as we close in on target
				SET controlTrans_X TO MIN (1.0, 1.0 * (ABS(mnv_Rend:NORMAL) / 4.0)).
				IF controlTrans_X < 0.05 SET controlTrans_X TO 0.05.
				IF mnv_rend:NORMAL > 0.0 SET controlTrans_X TO -controlTrans_X.
			
				// finished:
				IF ABS(mnv_Rend:NORMAL) < 0.01 {
					missionLog("CPU: X burn complete.").
					SET controlTrans_X TO 0.0.
				}
			}

			IF ABS(controlTrans_Y) > 0.0 {
				// reduce thrust as we close in on target
				SET controlTrans_Y TO MIN (1.0, 1.0 * (ABS(mnv_Rend:RADIALOUT) / 4.0)).
				IF controlTrans_Y < 0.05 SET controlTrans_Y TO 0.05.
				IF mnv_rend:RADIALOUT > 0.0 SET controlTrans_Y TO -controlTrans_Y.
			
				// finished:
				IF ABS(mnv_Rend:RADIALOUT) < 0.01 {
					missionLog("CPU: Y burn complete.").
					SET controlTrans_Y TO 0.0.
				}
			}

			IF ABS(controlTrans_Y) > 0.0 {
				// reduce thrust as we close in on target
				SET controlTrans_Y TO MIN (1.0, 1.0 * (ABS(mnv_Rend:RADIALOUT) / 4.0)).
				IF controlTrans_Y < 0.05 SET controlTrans_Y TO 0.05.
				IF mnv_rend:RADIALOUT > 0.0 SET controlTrans_Y TO -controlTrans_Y.
			
				// finished:
				IF ABS(mnv_Rend:RADIALOUT) < 0.01 {
					missionLog("CPU: Y burn complete.").
					SET controlTrans_Y TO 0.0.
				}
			}
			
			// finished:
			IF controlTrans_X + controlTrans_Y + controlTrans_Z <= 0.0 {
				SET stateFunction to Mode_NullVee_O@.
			}

			RETURN.
	}
	
	// else just waiting
	SET ui_BurnIn TO mnv_Rend:ETA.
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
    IF SHIP:ANGULARVEL:MAG < 0.005 {
		MissionLog("Rates nulled").
        SET stateFunction to Mode_X_N@.
        RETURN.
    }

	RETURN.

}

// end program, reboot?
LOCAL FUNCTION Mode_X_N {
    missionLog("Mode_X_N").
	
	SET SHIP:CONTROL:PILOTMAINTHROTTLE to 0.0.
    SET SHIP:CONTROL:NEUTRALIZE to TRUE.
	
	UNLOCK THROTTLE.
    UNLOCK STEERING.
	WAIT 1.
	
    SET RCS to initialRCS.
	SET SAS to initialSAS.

	missionLog("CTRL-C to END PROGRAM").

    IF pauseGameWhenFinished AND NOT ABORT {
        KUNIVERSE:PAUSE().
    }

    SET stateFunction to {}.
    RETURN.
	
	// TODO: transition to docking program where we will:
	// confirm mission docking port is available
	// dock with port
	
}


// utility stuff:
// orient to sun-facing?


// Calculates when in time the mean of a given burn is done. 
// For example a 10s burn with constant acceleration will have a burn mean of 5s.
// With constantly rising acceleration it would be closer to 7s.
// Line up the burn mean with the maneuver node to hit the targeted change with accuracy 
GLOBAL FUNCTION GetBurntime {
	PARAMETER deltV,  							// delta v of mnv
			  F IS SHIP:AVAILABLETHRUSTAT(0),	// available thrust for mnv
			  si IS SHIP:ENGINES[0]:ISPAT(0).	// isp of engines providing thrust

	// thrust 
	//LOCAL F TO SHIP:AVAILABLETHRUSTAT(0).
	
	// ISP
	//LOCAL si TO SHIP:ENGINES[0]:ISPAT(0)
	
	// mass flow
	LOCAL m_d TO F / (si * 9.81).
	
	// starting mass
	LOCAL m_0 TO SHIP:MASS.
	
	// calculate burn time
	LOCAL t_1 TO - (CONSTANT:E^(ln(m_0)-(deltV*m_d)/F)-m_0)/m_d.
	
	// calculate mean burn time
	LOCAL t_m TO (m_0*ln((m_d*t_1-m_0)/-m_0)+m_d*t_1)/(m_d*ln((m_0-m_d*t_1)/m_0)).
	
	RETURN LEXICON("MEAN", t_m, "TOTAL", t_1).

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













