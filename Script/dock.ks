@LAZYGLOBAL OFF.
SET CONFIG:IPU TO 2000.0.

{  	// this is a library of docking procedures, adapted from work by nuggreat

	// call Config to indicate the port on the active vessel and its target,
	// the offset distances desired for each facing direction, whether or not 
	// to rotate your ship to match the port orientation, and optionally, 
	// the amount of relative roll you want for the docked vessels.

	// call Exec to execute a translation maneuver using RCS that will take you 
	// from the SHIP:POSITION to one described by your configure command.

	LOCAL dock IS LEXICON(
		"EXEC", Exec@,
		"CONFIGURE", Configure@,
		"STOP", Full_Stop@
	).

	// does this need to be a queue?
	LOCAL taskList IS LIST().
	LOCAL scriptData IS LEXICON("DONE", FALSE).

	// lexicon of needed values to run translation function
	LOCAL translateData IS LEX("steerVec", SHIP:FACING:FOREVECTOR,
							   "foreVal", 0,
							   "topVal", 0,
							   "starVal", 0,
							   "roll", 0,
							   "maxSpeed", 1,
							   "accel", 0.05,
							   "stop", FALSE,
							   "rotate", TRUE,
							   "doTumbleComp",FALSE).

	// PID setup PIDLOOP(kP,kI,kD,min,max)
	LOCAL translationPIDs IS LIST("Fore","Star","Top").
	LOCAL PID IS LEX("Fore",PIDLOOP(4,0.1,0.01,-1,1),
					"Star",PIDLOOP(4,0.1,0.01,-1,1),
					"Top",PIDLOOP(4,0.1,0.01,-1,1),
					"Eng",PIDLOOP(1,0.02,0.05,0,1)).

	// get the total relative velocity and the directional components of that velocity
	// for the port or vessel under control and its target (port or vessel).
	LOCAL FUNCTION Axis_Speed {
		PARAMETER shipPoint,	// the craft to calculate the speed of (craft using RCS)
				  targetPoint.	// the target the speed is relative to
		
		// relativeSpeedVec is the speed as reported by the navball in target mode 		
		LOCAL localStation IS target_craft(targetPoint). 
		LOCAL localCraft IS target_craft(shipPoint).
		LOCAL relativeSpeedVec IS localCraft:VELOCITY:ORBIT - localStation:VELOCITY:ORBIT.		
		
		LOCAL craftFacing IS localCraft:FACING.
		IF shipPoint:ISTYPE("DOCKINGPORT") { SET craftFacing TO shipPoint:PORTFACING. }
		
		// the various directional components of that relative speed vector
		LOCAL speedFor IS VDOT(relativeSpeedVec, craftFacing:FOREVECTOR).	// positive is moving forwards, negative is moving backwards
		LOCAL speedTop IS VDOT(relativeSpeedVec, craftFacing:TOPVECTOR).	// positive is moving up, negative is moving down
		LOCAL speedStar IS VDOT(relativeSpeedVec, craftFacing:STARVECTOR).	// positive is moving right, negative is moving left
		
		RETURN LIST(relativeSpeedVec, speedFor, speedTop, speedStar).
	}

	// gets the total distance between the control point and its target, along with the 
	// quasi-cartesian values that make up that vector
	LOCAL FUNCTION Axis_Distance {
		PARAMETER shipPoint,	// port that all distances are relative to (craft using RCS)
				  targetPoint.	// port you want to dock to

		LOCAL craftFacing IS target_craft(shipPoint):FACING.
		IF shipPoint:ISTYPE("DOCKINGPORT") { SET craftFacing TO shipPoint:PORTFACING. }

		LOCAL distVec IS targetPoint:POSITION - shipPoint:POSITION.			// vector pointing at the station port from the craft port

		LOCAL dist IS distVec:MAG.
		LOCAL distFor IS VDOT(distVec, craftFacing:FOREVECTOR).		// if positive then station port is ahead of craft port, (negative is behind)
		LOCAL distTop IS VDOT(distVec, craftFacing:TOPVECTOR).		// if positive then station port is above of craft port, (negative is below)
		LOCAL distStar IS VDOT(distVec, craftFacing:STARVECTOR).	// if positive then station port is right of craft port, (negative is left)

		RETURN LIST(dist,distFor,distTop,distStar).
	}
	
	// if the target is a port, get the vessel it belongs to
	LOCAL FUNCTION Target_Craft {
		PARAMETER tar.
		IF NOT tar:ISTYPE("Vessel") { RETURN tar:SHIP. }
		RETURN tar.
	}

	LOCAL FUNCTION Has_Valid_Target {
		IF HASTARGET AND NOT TARGET:ISTYPE("Body") RETURN TRUE.
		RETURN FALSE.
	}

	// release controls
	LOCAL FUNCTION Shutdown_Stack {
		PRINT "DOCK: shutting down".
	
		RCS OFF.
		UNLOCK STEERING.
		UNLOCK THROTTLE.
		SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
		SET SHIP:CONTROL:FORE TO 0.
		SET SHIP:CONTROL:TOP TO 0.
		SET SHIP:CONTROL:STARBOARD TO 0.
		SET scriptData:DONE TO TRUE.
		RETURN TRUE.
	}

	LOCAL alignment IS LEXICON(
				"DURATION", LEXICON("maxError", 1,
									"careAboutRoll", FALSE,
									"alignedTime", TIME:SECONDS )).

	// wait until steering is aligned with what it is locked to
	LOCAL FUNCTION Steering_Aligned_Duration {
		LOCAL dataLex IS alignment:DURATION.
		PARAMETER setThis IS FALSE,
 				  maxError IS dataLex["maxError"],
				  careAboutRoll IS dataLex["careAboutRoll"].
	
		IF setThis {
			SET dataLex["maxError"] TO maxError.
			SET dataLex["careAboutRoll"] TO careAboutRoll.
			SET dataLex["alignedTime"] TO TIME:SECONDS.
			RETURN 0.
		} ELSE {
			LOCAL localTime IS TIME:SECONDS.
			LOCAL steerError IS ABS(STEERINGMANAGER:ANGLEERROR).

			IF careAboutRoll {
				SET steerError TO steerError + ABS(STEERINGMANAGER:ROLLERROR).
			}
			IF steerError > maxError {
				SET dataLex["alignedTime"] TO localTime.
			}

			RETURN localTime - dataLex["alignedTime"].
		}
	}

	// figure out how much to mash the gas based on how far we are away from the target
	LOCAL FUNCTION Accel_Dist_To_Speed {
		PARAMETER accel,
				  dist,
				  speedLimit,
				  deadZone IS 0.

		LOCAL localAccel IS accel.
		LOCAL posNeg IS 1.
		IF dist < 0 { SET posNeg TO -1. }
		IF (deadZone <> 0) AND (ABS(dist) < deadZone) { SET localAccel to accel / 10. }
		RETURN MIN(MAX((SQRT(2 * ABS(dist) / localAccel) * localAccel) * posNeg,-speedLimit),speedLimit).
	}

	// fire RCS to get us where we want
	LOCAL FUNCTION Translation_Control {
		PARAMETER desiredVelocityVec,
				  shipPoint,
				  targetPoint.
		
		RCS ON.
		WAIT 0.
		
		LOCAL shipFacing IS SHIP:FACING.
		LOCAL axisSpeed IS Axis_Speed(shipPoint,targetPoint).
	
		SET PID["Fore"]:SETPOINT TO VDOT(desiredVelocityVec,shipFacing:FOREVECTOR).
		SET PID["Top"]:SETPOINT TO VDOT(desiredVelocityVec,shipFacing:TOPVECTOR).
		SET PID["Star"]:SETPOINT TO VDOT(desiredVelocityVec,shipFacing:STARVECTOR).
	
		SET SHIP:CONTROL:FORE TO PID["Fore"]:UPDATE(TIME:SECONDS, axisSpeed[1]).
		SET SHIP:CONTROL:TOP TO PID["Top"]:UPDATE(TIME:SECONDS, axisSpeed[2]).
		SET SHIP:CONTROL:STARBOARD TO PID["Star"]:UPDATE(TIME:SECONDS, axisSpeed[3]).
	}

	// killswitch engaged
	LOCAL FUNCTION Full_Stop {
		PRINT "Stopping translation".
		SET translateData["stop"] TO TRUE.
	}

	// move to desired location
	LOCAL FUNCTION Translate {
		PARAMETER translateState,
				  shipPoint,
				  targetPoint.

		// if we're docked we're done
		IF shipPoint:ISTYPE("DOCKINGPORT") AND
		   shipPoint:STATE:CONTAINS("Docked") {
				taskList:ADD(shutdown_stack@).
				RETURN TRUE.
        }
		
		// if somebody yells "Stop" 
	    IF translateData["stop"] {
			SET translateData["stop"] TO FALSE.
			taskList:ADD(shutdown_stack@).
			RETURN TRUE.
		}

		// the vector straight out from the target
		LOCAL targetFacing TO targetPoint:FACING.
		IF targetPoint:ISTYPE("DOCKINGPORT") SET targetFacing TO targetPoint:PORTFACING.
		
		LOCAL targetFacingFor TO targetFacing:FOREVECTOR.
		LOCAL targetFacingTop TO targetFacing:TOPVECTOR.
		LOCAL targetFacingStar TO targetFacing:STARVECTOR.

		IF translateData["Rotate"] {
			// this gets us pointing in the opposite vector with desired roll
			SET STEERINGMANAGER:MAXSTOPPINGTIME TO 0.1.
			SET translateData["steerVec"] TO ANGLEAXIS(translateData["Roll"], -targetFacingFor) * LOOKDIRUP(-targetFacingFor, targetFacingTop).
		}

		// let's get started, shall we?
		IF translateState = 0 {
			LOCK STEERING TO translateData["steerVec"].

			// make sure we get reasonably aligned before we start trying to translate 
			Steering_Aligned_Duration(TRUE, 5, TRUE).
			
			// prevent accidentally bumping the throttle
			LOCK THROTTLE TO 0.
	
			// reset the PID controllers
			FOR key IN translationPIDs { PID[key]:RESET().}

			// create the next step in our task list
			taskList:ADD(translate@:BIND((translateState + 1), shipPoint, targetPoint)).

			// move on, pilot
			RETURN TRUE.
		
		} ELSE IF translateState = 1 { // have we stopped flopping around?

			IF Steering_Aligned_Duration() > 1 {
				taskList:ADD(translate@:BIND((translateState + 1), shipPoint, targetPoint)).
				RETURN TRUE.	// go on to next step
			} ELSE {
				RETURN FALSE.  	// I think this means repeat this step?
			}
    
		} ELSE IF translateState = 2 { // get moving!

			LOCAL targetPosition IS targetPoint:POSITION.
			LOCAL vecToTarget IS targetPosition - shipPoint:POSITION.
            LOCAL desiredVelocityVec IS v(0,0,0).

			// set the desired offset forward of the target port:
			SET targetPosition TO targetPosition + (targetFacingFor * translateData["foreVal"]).

			// set the desired offset vertical of the target port:
			SET targetPosition TO targetPosition + (targetFacingTop * translateData["topVal"]).

			// set the desired offset lateral of the target port:
			SET targetPosition TO targetPosition + (-targetFacingStar * translateData["starVal"]).

			// this is the way
            SET vecToTarget TO targetPosition - shipPoint:POSITION.
			
			// how fast?
            LOCAL speedCoeficent IS accel_dist_to_speed(translateData["accel"], vecToTarget:MAG, translateData["maxSpeed"], 0).
			SET desiredVelocityVec TO desiredVelocityVec + vecToTarget:NORMALIZED * speedCoeficent.
			
			// make sure not TOO fast
            IF desiredVelocityVec:MAG > translateData["maxSpeed"] {
                SET desiredVelocityVec TO desiredVelocityVec:NORMALIZED * translateData["maxSpeed"].
            }
			
			PRINT "Speed: " + ROUND(desiredVelocityVec:MAG, 2) + "":PADRIGHT(10) AT (1,26).
			PRINT "Dist:  " + ROUND(vecToTarget:MAG, 2) + "":PADRIGHT(10) AT (1,27).
			
			// if we are close 'nuff?
			IF desiredVelocityVec:MAG < 0.1 AND vecToTarget:MAG < 0.1 {
				PRINT "DOCK: close nuff".
				taskList:ADD(shutdown_stack@).
				RETURN TRUE.
			}

			// hopefully we never get into this bad place
            IF translateData["doTumbleComp"] {
                LOCAL tangentVel IS tangent_velocity_vector(targetPoint).
                SET desiredVelocityVec TO desiredVelocityVec + tangentVel.
            } 
            
			// engage RCS to do the thing
			Translation_Control(desiredVelocityVec, shipPoint, targetPoint).
            RETURN FALSE.  // fire until we're done
		
		} ELSE IF translateState > 2 { // failsafe
			taskList:ADD(shutdown_stack@).
			RETURN TRUE.
		}		
	}
		
	// call this to set the desired distances and orientation between the ship's port and the target port
	LOCAL FUNCTION Configure {
		PARAMETER shipPoint,				// the port on the vessel under control
				  targetPoint IS TARGET,	// the target port or vessel
				  offsets IS LEXICON("FORE", 0, "TOP", 0, "STAR", 0), // desired standoff distance
				  rotate IS TRUE,		// if true, rotate to face the target port
				  accel IS 0.05, 		// calculates how enthusiastically to thrust
				  maxSpeed IS 1.0, 		// what is our speed limit
				  setRoll IS 0.			// set the relative roll angle between the two ports

		IF Has_Valid_Target {
			SET translateData["steerVec"] TO SHIP:FACING:FOREVECTOR.
			SET translateData["foreVal"] TO offsets:FORE.
			SET translateData["topVal"] TO -offsets:TOP. // why inverse?
			SET translateData["starVal"] TO offsets:STAR.	
			SET translateData["roll"] TO setRoll.
			SET translateData["Rotate"] TO rotate.
			SET translateData[""] TO maxSpeed.
			SET translateData["accel"] TO accel.
		
			taskList:ADD(translate@:BIND(0, shipPoint, targetPoint)).
			shipPoint:CONTROLFROM().
			RETURN TRUE.
		}
		
		PRINT "DOCK: Invalid Params".
		RETURN FALSE.
	}

	LOCAL FUNCTION Exec {
		
		UNTIL scriptData:DONE AND taskList:LENGTH = 0 {
			// update the UI?
		
			IF taskList:LENGTH > 0 {
				FROM { LOCAL i IS taskList:LENGTH -1. } UNTIL i < 0 STEP { SET i TO i - 1. } DO {
					IF taskList[i]:CALL() {
						taskList:REMOVE(i).
					}
				}
			}

			WAIT 0.
			IF ABORT { Shutdown_Stack(). }
		}		

		SET scriptData:DONE TO FALSE.
	}

	EXPORT(dock).
	
}