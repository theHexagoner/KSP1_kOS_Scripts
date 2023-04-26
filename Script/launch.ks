@LAZYGLOBAL OFF.

{

	LOCAL launch IS LEXICON(
		"Find_Window", Find_Window@,
		"Blastoff", Blastoff@
	).

	LOCAL FUNCTION Find_Window {
		PARAMETER tVessel IS 0,
				  launchToInclination IS 0,
				  launchToApoapsis IS 100000,
				  launchToLAN IS 0,
				  ascentTime IS 0,	// ascent flight-time will need to be determined for each mission
				  ascentDegs IS 0,	// how far downrange will the ship go during ascent?
				  soupFactor IS 0.	// how long does it take us to get above the thick atmosphere?

		IF tVessel:ISTYPE("Vessel") {
			SET launchToInclination TO tVessel:OBT:INCLINATION.
			SET launchToApoapsis TO tVessel:OBT:SEMIMAJORAXIS.
			SET launchToLAN TO tVessel:OBT:LAN.
		}

		IF NOT latIncOk(SHIP:LATITUDE, launchToInclination) SET launchToInclination TO launchToInclination - ABS(SHIP:LATITUDE).

		// if the inclination is 0 or 180 the azimuth is 90 or 270
		LOCAL laz IS launchToInclination + 90.

		IF launchToInclination <> 0 AND launchToInclination <> 180 {
			// fart opposite this general direction
			SET laz TO Get_Launch_Azimuth(launchToInclination, launchToApoapsis).		
		}
		
		LOCAL MaxPhase IS 0.
		LOCAL MinPhase IS 0.
		LOCAL phaseDuration IS 0.
		
		IF tVessel:ISTYPE("Vessel") {
		
			LOCAL tDPS IS 360 / tVessel:OBT:PERIOD. 	// how fast is the target vessel moving?
			LOCAL tDegs IS ascentTime * tDPS.			// we can calculate how far the target will move (degrees) during our ascent
		
			// we need to subtract our distance travelled from that figure
			// we also need to take some out to ensure that we come up -behind- the KSS
			// maxPhase seems to be ~ 18 deg.
			SET maxPhase TO tdegs -ascentDegs -3.0.  
	
			// let's try a 15 degree window and see how often launches come up
			// maybe increase the range if no acceptable window is found within so many iterations?
			SET minPhase TO maxPhase - 15.0.

			// how many seconds is this window open?
			SET phaseDuration TO (maxPhase - minPhase) * tDPS.
		}
	
		// loop until we find the first suitable window.
		LOCAL etaSecs IS -1.
		LOCAL iter IS 1.
		LOCAL validWindow IS FALSE.
		
		LOCAL eta_to_AN IS 1 - phaseDuration.
		LOCAL eta_to_DN IS 1 - phaseDuration.
		LOCAL ts_AtTime IS 0.0.
	
		UNTIL validWindow {
		
			IF launchToInclination <> 0 AND launchToInclination <> 180 {
				SET eta_to_AN TO Get_ETA_For_Orbital_Plane(launchToInclination, launchToLAN, TRUE, iter).
				SET eta_to_DN TO Get_ETA_For_Orbital_Plane(launchToInclination, launchToLAN, FALSE, iter).
			} ELSE {	
				// add some time per iteration
				SET eta_to_AN TO eta_to_AN + phaseDuration.
				SET eta_to_DN TO eta_to_DN + phaseDuration.
			}
			
			// if we are going to launch to rendezvous we need to also check phase alignment
			IF tVessel:ISTYPE("Vessel") {

				// we prefer a northerly launch so check that first	
				SET ts_AtTime TO TIME:SECONDS + eta_to_AN - soupFactor.
				LOCAL anPA IS Get_Future_Phase_Angle(ts_AtTime, tVessel).
				
				IF anPA < maxPhase AND anPA > minPhase  {
					SET etaSecs TO eta_to_AN.
				} ELSE {
					// if that didn't work try again with a southerly launch
					
					SET ts_AtTime TO TIME:SECONDS + eta_to_DN - soupFactor.
					LOCAL dnPA IS Get_Future_Phase_Angle(ts_AtTime, tVessel).
					
					IF dnPA < maxPhase AND dnPA > minPhase {
						SET etaSecs TO eta_to_DN.
						SET laz TO mAngle(180 - laz).
					} ELSE {
						SET iter TO iter + 1.
					}
				}
			} ELSE { // we can just launch whenever we are on-plane
				SET etaSecs TO MIN(eta_to_AN, eta_to_DN).
				IF etaSecs < ascentTime SET etaSecs TO MAX(eta_to_AN, eta_to_DN).
			}
			
			SET validWindow TO etaSecs > ascentTime.
			IF NOT validWindow SET iter TO iter + 1.
			WAIT 0.
		}

		RETURN LEXICON("AZIMUTH", laz, "L_ETA", (etaSecs - soupFactor)).

	}

	// Calculates the launch azimuth for a "northerly" launch
	LOCAL FUNCTION Get_Launch_Azimuth {
		PARAMETER launchToInclination,
				  launchToApoapsis.
	
		// This IS what our launch azimuth WOULD be IF the planet weren't moving.
		LOCAL launchAzimuthInertial IS ARCSIN( COS(launchToInclination) / COS(SHIP:LATITUDE) ).
	
		// To compensate for the rotation of the planet, we need to estimate the orbital velocity we're going to gain during ascent. 
		// We can ballpark this by assuming a circular orbit at the targeted apoapsis, but there will necessarily be some 
		// very small error, which we will correct during the closed-loop portion of our ascent.
		LOCAL vApproximate IS SQRT( SHIP:BODY:MU / ( SHIP:BODY:RADIUS + launchToApoapsis ) ).
	
		// Construct the components of the launch vector in the rotating frame. 
		// NOTE: In this frame the x axis points north and the y axis points east because KSP
		LOCAL x IS vApproximate * COS(launchAzimuthInertial).
		LOCAL y IS vApproximate * SIN(launchAzimuthInertial) - SHIP:VELOCITY:ORBIT:MAG * COS(SHIP:LATITUDE).
	
		// Finally, the launch azimuth IS the angle of the launch vector we just computed, measured from the x (north) axis: 
		RETURN ARCTAN2(y, x).
	}

	// Calculates the estimated time (in seconds) until the orbital plane described by the LAN and inclination
	// of the target orbital plan will pass over the ship's location
	LOCAL FUNCTION Get_ETA_For_Orbital_Plane {
		PARAMETER launchToInclination,	// inclination of target orbit
				  launchToLAN,			// LAN of target orbit
				  is_AN,				// true = return the ETA for "northerly" launch
				  iter IS 1.
	
		LOCAL etaSecs IS -1.
	
		// The relative longitude measures the angular difference between the longitude of the launch site 
		// and the longitude of ascending node of an orbit described by the target orbital inclination
		LOCAL relativeLong IS ARCSIN(TAN(SHIP:LATITUDE)/TAN(launchToInclination)). 
		
		// IF the target orbit IS descending:
		IF NOT is_AN { SET relativeLong TO 180 - relativeLong. }
	
		// adjust for the geographic rotational variance from universal
		LOCAL geoLAN IS mAngle(launchToLAN + relativeLong - BODY:ROTATIONANGLE).
		
		// get the angle between our current geographical longitude and the 
		// geographical longitude where the target orbital plane meets our latitude
		LOCAL node_angle IS mAngle(geoLAN - SHIP:LONGITUDE).
	
		// calculate how long the rotation of Kerbin will take to rotate us under the target orbit
		SET etaSecs TO ((node_angle / 360) * BODY:ROTATIONPERIOD). 
		
		// if we didn't find a good window in the first orbital period, keep looking
		IF iter > 1 SET etaSecs TO  etaSecs + (-BODY:ROTATIONPERIOD + (iter * BODY:ROTATIONPERIOD)).
	
		RETURN etaSecs.
	}

	// normalize an angle to the range 0 to 360
	LOCAL FUNCTION mAngle {
		PARAMETER angle.
		UNTIL angle >= 0 { SET angle TO angle + 360. }
		RETURN MOD(angle, 360).
	}

	LOCAL FUNCTION Get_Future_Phase_Angle {
		PARAMETER ts_AtTime,	// seconds at epoch
				  tVessel.
		
		LOCAL shipRad TO (Get_Geoposition_At(SHIP:GEOPOSITION, ts_AtTime) - BODY:POSITION):NORMALIZED.
		LOCAL tRad TO (POSITIONAT(tVessel, ts_AtTime) - BODY:POSITION):NORMALIZED.
	
		LOCAL binormal IS VCRS(tRad, VELOCITYAT(tVessel, ts_AtTime):ORBIT:NORMALIZED):NORMALIZED.
		LOCAL phase IS VANG(tRad, VXCL(binormal, shipRad):NORMALIZED).
		LOCAL signVector IS VCRS(tRad, (shipRad):NORMALIZED).
		LOCAL sign IS VDOT(binormal, signVector).
		
		IF sign < 0 {
			RETURN -phase.			// negative indicates "the target is behind" in orbit
			//RETURN 360 - phase. 	// this is how mechjeb reports, I think
		}
		ELSE {
			RETURN phase. 			// positive values indicate "the target is ahead" in orbit
		}		 
	}

	// courtesy of u/JitteryJet
	// Calculates the position vector of the spot above (or below) a geographical coordinate at some time in the future.
	LOCAL FUNCTION Get_Geoposition_At {
		PARAMETER geo,			// geoposition
				  ts_AtTime.	// seconds from epoch
				
		LOCAL duration IS ts_AtTime - TIME:SECONDS. // how long we twist
		LOCAL diff IS (duration / BODY:ROTATIONPERIOD) * 360.
			
		LOCAL futureLong IS geo:LNG + diff. 
		LOCAL futureR IS LATLNG(geo:LAT, futureLong):POSITION.
		RETURN futureR.
	}

	// return true if we can reach this inclination from this latitude
	LOCAL FUNCTION latIncOk {
		PARAMETER lat, // launch latitude
				  inc. // desired inclination
		
		RETURN (inc > 0 AND ABS(lat) < 90 AND MIN(inc, 180-inc) >= ABS(lat)).
	}


	LOCAL FUNCTION Blastoff {
		// is there something to do here that shouldn't be done in the mission program?
		RETURN.
	}

	Export(launch).

}