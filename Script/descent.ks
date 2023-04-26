@LAZYGLOBAL OFF.

{
	LOCAL NIL IS 0.0001.
	
	LOCAL land_slip IS 0.05. // max transverse speed at touchdown (m/s)
	LOCAL land_descend is 10.0. // max vertical speed during final descent (m/s)

	LOCAL descent IS LEXICON(
		"Deorbit_Burn", Deorbit_Burn@,
		"Calc_Brakepoint", Calc_Brakepoint@,
		"Braking_Burn", Braking_Burn@,
		"Landing_Burn", Landing_Burn@
	).

	// quit orbiting
	LOCAL FUNCTION Deorbit_Burn {
		LOCK THROTTLE TO 1.
		UNTIL SHIP:STATUS <> "ORBITING" WAIT 0.
		
		LOCK THROTTLE TO 0.
		PRINT "Jeb: Deorbit Complete".
	}

	LOCAL FUNCTION Calc_Brakepoint {
		PARAMETER retroMargin IS 500.0,
				  shipISP IS 345.0.

		LOCAL simResults IS LEX("pos",SHIP:POSITION,"seconds", 30).
		LOCAL tsMax IS 0.5.
		LOCAL deltaTime IS 0.5.
		LOCAL simDelay IS 1.0.
		LOCAL prediction IS LEXICON("BURNALT", FALSE, "FLAT", FALSE).

		LOCAL updatePrediction IS {
			PARAMETER simPos.

			LOCAL stopPos IS SHIP:POSITION + simPos.
			LOCAL stopGeo IS SHIP:BODY:GEOPOSITIONOF(stopPos).
			LOCAL radAlt IS SHIP:BODY:ALTITUDEOF(stopPos) - stopGeo:TERRAINHEIGHT.
			LOCAL slope IS slope_calculation(stopGeo).
			
			PRINT "Rad alt:    " + RoundZero(radAlt, 1) AT (10, 20).
			PRINT "Slope:      " + RoundZero(slope, 1) AT (10, 21).

			SET prediction:BURNALT TO radAlt < retroMargin.
			SET prediction:FLAT TO (slope < 3) .
			
			RETURN.
		}.

		UNTIL prediction:BURNALT AND prediction:FLAT {
			SET tsMax TO (tsMax + (simResults["seconds"] / 10)) / 2.
			SET simResults TO sim_land_vac(SHIP,shipISP,MIN(deltaTime,tsMax),deltaTime * simDelay).		
			updatePrediction(simResults["pos"]).
			WAIT 0.
		}

	}

	LOCAL FUNCTION Braking_Burn {
		PARAMETER retroMargin IS 500.0,
				  shipISP IS 345.0.
		
		LOCAL deltaTime IS 0.5.
		LOCAL timePre IS TIME:SECONDS.
		LOCAL tsMax IS 0.5.
		LOCAL simDelay IS 1.0.
		LOCAL stopGap IS 0.
		LOCAL retroMarginLow IS retroMargin - 100.
		
		LOCAL simResults IS LEX("pos",SHIP:POSITION,"seconds", 30).

		LOCAL controlThrottle IS 0.
		LOCK THROTTLE TO controlThrottle.
		LOCK STEERING TO LOOKDIRUP(SHIP:SRFRETROGRADE:VECTOR, SHIP:UP:VECTOR).

		SET controlThrottle TO 1.
		SET simDelay TO 0.
	
		UNTIL VERTICALSPEED > -2 AND GROUNDSPEED < 3 {
			LOCAL localTime IS TIME:SECONDS.
			SET deltaTime TO (localTime - timePre + deltaTime) / 2.
			SET timePre TO localTime.
			LOCAL shipPosOld IS SHIP:POSITION - SHIP:BODY:POSITION.
			LOCAL initialMass IS SHIP:MASS.
			
			SET tsMax TO (tsMax + (simResults["seconds"] / 10)) / 2.
			SET simResults TO sim_land_vac(SHIP,shipISP,MIN(deltaTime,tsMax),deltaTime * simDelay).

			LOCAL stopPos IS (SHIP:BODY:POSITION + shipPosOld) + simResults["pos"].
			SET stopGap TO SHIP:BODY:ALTITUDEOF(stopPos) - SHIP:BODY:GEOPOSITIONOF(stopPos):TERRAINHEIGHT.
			
			SET controlThrottle TO MIN(100 / MAX((stopGap - retroMarginLow), 100),1).
			
			LOCAL slope IS slope_calculation(SHIP:BODY:GEOPOSITIONOF(stopPos)).
			
			// show some info on the sreen:
			
			PRINT "Terrain Gap:    " + RoundZero(stopGap, 0)													AT (10, 20).
			PRINT "Dv Needed:      " + RoundZero(shipISP * 9.80665 * LN(initialMass/simResults["mass"]), 0)		AT (10, 21).
				PRINT "init mass:      " + RoundZero(initialMass, 1) 											AT (15, 22).
				PRINT "sim mass:      " + RoundZero(simResults["mass"], 1) 										AT (15, 23).
		
			PRINT "time to Stop:   " + RoundZero(simResults["seconds"], 1)										AT (10, 24).
			PRINT "Time Per Sim:   " + RoundZero(deltaTime, 2)													AT (10, 25).
			PRINT "Steps Per Sim:  " + simResults["cycles"]														AT (10, 26).
			PRINT "Vert Speed:     " + RoundZero(VERTICALSPEED, 0)												AT (10, 27).
			
			WAIT 0.
		}
	
		PRINT "Jeb: braking burn complete".
		
		UNLOCK THROTTLE.
		SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
	
	}

	// intercept the ground
	LOCAL FUNCTION Landing_Burn {
		PARAMETER margin IS 2.0. // so we can adjust for how tall is the ship
				
		LOCAL shipThrust IS SHIP:AVAILABLETHRUST * 0.90.
		LOCAL shipAcc IS (shipThrust / SHIP:MASS).
		LOCAL sucideMargin IS margin + 17.5.
		LOCAL decentLex IS descent_math(shipThrust).
		
		LOCAL landing_PID IS PIDLOOP(1.1,0.1,0.1,0,1).//was(0.5,0.1,0.01,0,1)
		LOCAL westVector IS ANGLEAXIS(-90, SHIP:UP:FOREVECTOR) * SHIP:NORTH:FOREVECTOR.
	
		LEGS ON.

		LOCK STEERING TO LOOKDIRUP(SHIP:SRFRETROGRADE:FOREVECTOR, westVector).
		LOCK THROTTLE TO landing_PID:UPDATE(TIME:SECONDS,VERTICALSPEED).

		UNTIL ALT:RADAR < sucideMargin {	//vertical suicide burn stopping at about 20m above surface
			SET decentLex TO descent_math(shipThrust).
			SET shipAcc TO decentLex["acc"].
			SET landing_PID:SETPOINT TO MIN(-shipAcc * SQRT(ABS(2 * (ALT:RADAR - sucideMargin) / shipAcc)),-0.5).

			LOCAL slope IS slope_calculation(SHIP:GEOPOSITION).
			
			PRINT "Slope:        " + RoundZero(slope, 1) + "":PADRIGHT(10)											AT (10, 19).
			PRINT "setPoint:     " + RoundZero(landing_PID:SETPOINT,2) + "":PADRIGHT(10)							AT (10, 20).
			PRINT "vSpeed:       " + RoundZero(VERTICALSPEED,2) + "":PADRIGHT(10)									AT (10, 21).
			PRINT "Altitude:     " + RoundZero(ALT:RADAR - sucideMargin,1) + "":PADRIGHT(10)						AT (10, 22).
			PRINT "Stoping Dist: " + RoundZero(decentLex["stopDist"],1)+ "":PADRIGHT(10)							AT (10, 23).
			PRINT "Stoping Time: " + RoundZero(decentLex["stopTime"],1)+ "":PADRIGHT(10)							AT (10, 24).
			PRINT "Dist to Burn: " + RoundZero(ALT:RADAR -sucideMargin -decentLex["stopDist"],1) + "":PADRIGHT(10) 	AT (10, 25).
			WAIT 0.
		}

		

		LOCAL controlSteering IS LOOKDIRUP(SHIP:SRFRETROGRADE:FOREVECTOR:NORMALIZED + ( SHIP:UP:FOREVECTOR:NORMALIZED * 3), westVector).
		LOCK STEERING TO controlSteering.
		
		UNTIL STATUS = "LANDED"  {	//slow decent until touchdown
			LOCAL decentLex IS descent_math(shipThrust).
		
			LOCAL vSpeedTar IS MIN(0 - (ALT:RADAR - margin - (ALT:RADAR * decentLex["stopTime"])) / (11 - MIN(decentLex["twr"],10)),-0.5).
			SET landing_PID:SETPOINT TO vSpeedTar.
		
			IF VERTICALSPEED < -1 {
				SET controlSteering TO LOOKDIRUP(SHIP:SRFRETROGRADE:FOREVECTOR:NORMALIZED + (SHIP:UP:FOREVECTOR:NORMALIZED * 3), westVector).
			} ELSE {
				LOCAL retroHeading IS heading_of_vector(SHIP:SRFRETROGRADE:FOREVECTOR).
				LOCAL adjustedPitch IS MAX(90-GROUNDSPEED,89).
				SET controlSteering TO LOOKDIRUP(HEADING(retroHeading,adjustedPitch):FOREVECTOR, westVector).
			}
			
			PRINT "Altitude:     " + RoundZero(ALT:RADAR - sucideMargin,1) + "":PADRIGHT(10)			AT (10, 22).
			PRINT "vSpeedTar: " + RoundZero(vSpeedTar,1) + "":PADRIGHT(10) 								AT (10, 26).
			PRINT "vSpeed:       " + RoundZero(VERTICALSPEED,2) + "":PADRIGHT(10)						AT (10, 21).

			WAIT 0.
		}
		
		BRAKES ON.
		PRINT "Holding Up Until Craft Stops Moving".
		LOCK THROTTLE TO 0.
		LOCK STEERING TO LOOKDIRUP(SHIP:UP:FOREVECTOR, westVector).
		WAIT UNTIL SHIP:VELOCITY:SURFACE:MAG < 0.1.
		
		WAIT 3.
		PRINT "Bob: decent program complete".
		WAIT 3.
		
		CLEARSCREEN.
		PRINT "Jeb: The Urkel has landed!".
		
		UNLOCK THROTTLE.
		UNLOCK STEERING.
		SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
		LIGHTS OFF.		
	
	}

	LOCAL FUNCTION RoundZero {
		PARAMETER n.
		PARAMETER desiredPlaces IS 0.

		LOCAL str IS ROUND(n, desiredPlaces):TOSTRING.

		IF desiredPlaces > 0 {
			LOCAL hasPlaces IS 0.
			IF str:CONTAINS(".") {
				SET hasPlaces TO str:LENGTH - str:FIND(".") - 1.
			} ELSE {
				SET str TO str + ".".
			}
			IF hasPlaces < desiredPlaces {
				FROM { LOCAL i IS 0. } UNTIL i = desiredPlaces - hasPlaces STEP { SET i TO i + 1. } DO {
					SET str TO str + "0".
				}
			}
		}

		RETURN str.
	}
	
	LOCAL FUNCTION sim_land_vac {//credit to dunbaratu for the orignal code
		PARAMETER
		ves,			//the craft to simulate for
		e_isp,			//the isp of the active engines
		t_deltaIn,		//time step for sim
		coast.			//a coast time with no thrust in seconds
		
		LOCAL t_delta IS MAX(t_deltaIn,0.02).		//making it so the t_delta can't go below 0.02s
		LOCAL GM IS ves:BODY:MU.					//the MU of the body the ship is in orbit of
		LOCAL b_pos IS ves:BODY:POSITION.			//the position of the body relative to the ship
		LOCAL t_max IS ves:AVAILABLETHRUST * 0.95.	//the thrust available to the ship
		LOCAL m IS ves:MASS.						//the ship's mass
		LOCAL vel IS ves:VELOCITY:SURFACE.			//the ship's velocity relative to the surface
		LOCAL prev_vel IS vel.
		LOCAL deltaM IS t_max / (9.80665 * e_isp) * t_delta.	// i.e. "delta mass"
		
		LOCAL pos IS V(0,0,0).
		LOCAL t IS 0.
		LOCAL cycles IS 0.
		
		IF coast > 0 {
			UNTIL t >= coast {	//advances the simulation of the craft with out burning for the amount of time defined by coast
				SET cycles TO cycles + 1.
				LOCAL up_vec IS (pos - b_pos).
			
			//	LOCAL up_unit IS up_vec:NORMALIZED.//vector from craft pointing at craft from body you are around
			//	LOCAL r_square IS up_vec:SQRMAGNITUDE.//needed for gravity calculation
			//	LOCAL localGrav IS GM / r_square.//gravitational acceleration at current height
			//	LOCAL a_vec IS - up_unit * localGrav.//gravatational acceleration as a vector
				LOCAL a_vec IS - up_vec:NORMALIZED * (GM / up_vec:SQRMAGNITUDE).
				// above commented math is merged to save on IPU during the sim
			
				SET prev_vel TO vel.//store previous velocity vector for averaging
				SET vel TO vel + a_vec * t_delta.//update velocity vector with calculated applied accelerations
			
				LOCAL avg_vel IS 0.5 * (vel + prev_vel).//average previous with current velocity vectors to smooth changes NOTE:might not be needed
			
				SET pos TO pos + avg_vel * t_delta.//change stored position by adding the velocity vector adjusted for time
			
				SET t TO t + t_delta.//increment clock
			}
		}
		
		UNTIL FALSE {	//retroburn simulation
			SET cycles TO cycles + 1.
			LOCAL up_vec IS (pos - b_pos).
		
			IF VDOT(vel, prev_vel) < 0 { break. }	//ends sim when velocity reverses
		
		//	LOCAL up_unit IS up_vec:NORMALIZED.//vector from craft pointing at craft from body you are around
		//	LOCAL r_square IS up_vec:SQRMAGNITUDE.//needed for gravity calculation
		//	LOCAL localGrav IS GM / r_square.//gravitational acceleration at current height
		//	LOCAL g_vec IS - up_unit*localGrav.//gravitational acceleration as a vector
		//	LOCAL eng_a_vec IS (t_max / m) * (- vel:NORMALIZED).//velocity vector imparted by engines calculated from thrust and mass along the negative of current velocity vector (retrograde)
		//	LOCAL a_vec IS eng_a_vec + g_vec.//adding engine acceleration and grav acceleration vectors to create a vector for all acceleration acting on craft
			LOCAL a_vec IS ((t_max / m) * (- vel:NORMALIZED)) - ((GM / up_vec:SQRMAGNITUDE) * up_vec:NORMALIZED).
			// above commented math is merged to save on IPU during the sim
		
			SET prev_vel TO vel.//store previous velocity vector for averaging
			SET vel TO vel + a_vec * t_delta.//update velocity vector with calculated applied accelerations
		
			LOCAL avg_vel is 0.5 * (vel+prev_vel).//average previous with current velocity vectors to smooth changes NOTE:might not be needed
		
			SET pos TO pos + (avg_vel * t_delta).//change stored position by adding the velocity vector adjusted for time
			SET m TO m - deltaM.//change stored mass for craft based on pre calculated change in mass per tick of sim
		
			IF m <= 0 { BREAK. }
			SET t TO t + t_delta.//increment clock
		}
		
		RETURN LEX("pos", pos,"vel", vel,"seconds", t,"mass", m,"cycles", cycles).
	}

	// the math needed for suicide burn and final decent
	LOCAL FUNCTION descent_math {	
		PARAMETER shipThrust.
		
		LOCAL localGrav IS SHIP:BODY:MU/(SHIP:BODY:RADIUS + SHIP:ALTITUDE)^2.		//calculates gravity of the body
		LOCAL shipAcceleration IS shipThrust / SHIP:MASS.							//ship acceleration in m/s
		LOCAL stopTime IS  ABS(VERTICALSPEED) / (shipAcceleration - localGrav).		//time needed to neutralize vertical speed
		LOCAL stopDist IS 1/2 * shipAcceleration * stopTime * stopTime.				//how much distance is needed to come to a stop
		LOCAL twr IS shipAcceleration / localGrav.									//the TWR of the craft based on local gravity
	
		RETURN LEX("stopTime",stopTime,"stopDist",stopDist,"twr",twr, "acc", shipAcceleration - localGrav).
	}

	LOCAL FUNCTION heading_of_vector { // heading_of_vector returns the heading of the vector (number range 0 to 360)
		PARAMETER vecT.
	
		LOCAL east IS VCRS(SHIP:UP:VECTOR, SHIP:NORTH:VECTOR).
		LOCAL trig_x IS VDOT(SHIP:NORTH:VECTOR, vecT).
		LOCAL trig_y IS VDOT(east, vecT).
		LOCAL result IS ARCTAN2(trig_y, trig_x).
	
		IF result < 0 {RETURN 360 + result.} ELSE {RETURN result.}
	}

	//returns the slope of p1 in degrees
	LOCAL FUNCTION slope_calculation {
		PARAMETER p1.
		LOCAL upVec IS (p1:POSITION - p1:BODY:POSITION):NORMALIZED.
		RETURN VANG(upVec,surface_normal(p1)).
	}
	
	// gets the "ground plane" of a point on a body
	LOCAL FUNCTION surface_normal {
		PARAMETER p1.
		LOCAL localBody IS p1:BODY.
		LOCAL basePos IS p1:POSITION.
	
		LOCAL upVec IS (basePos - localBody:POSITION):NORMALIZED.
		LOCAL northVec IS VXCL(upVec,LATLNG(90,0):POSITION - basePos):NORMALIZED * 3.
		LOCAL sideVec IS VCRS(upVec,northVec):NORMALIZED * 3.//is east
	
		LOCAL aPos IS localBody:GEOPOSITIONOF(basePos - northVec + sideVec):POSITION - basePos.
		LOCAL bPos IS localBody:GEOPOSITIONOF(basePos - northVec - sideVec):POSITION - basePos.
		LOCAL cPos IS localBody:GEOPOSITIONOF(basePos + northVec):POSITION - basePos.
		RETURN VCRS((aPos - cPos),(bPos - cPos)):NORMALIZED.
	}

	Export(descent).
}