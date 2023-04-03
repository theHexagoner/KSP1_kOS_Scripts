@LAZYGLOBAL OFF.

RUNONCEPATH("/common/lib_common.ks").
RUNONCEPATH("/common/lib_orbits.ks").

GLOBAL CLOSED_LOOP IS FALSE.
GLOBAL GUIDO IS LEXICON("Azimuth", 0.0, "PPROG", 90.0).

// how high IS up?
GLOBAL launchToApoapsis IS 115000.0. // m

// The pitch program end altitude IS the altitude, in meters, at which we level out to a pitch of 0° off the horizontal.
// this seems to be more or less constrained to the top of the atmosphere when using the sqrt solution for controlling pitch
GLOBAL pitchProgramEndAltitude IS 91500.0.  // meters

// show some stuff in the console when we get into the active guidance
GLOBAL velAtAPO IS 0.0.

// we need to account for how long it takes to build up significant horizontal velocity
// used to predict launch window for intercepting the KSS orbit
LOCAL halfLaunchSecs IS 80.

// This parameter controls the shape of the ascent curve.
LOCAL pitchProgramExponent IS  0.40.

// We are launching at the KSS, which is generally in an orbit inclined to 51.6 deg
LOCAL launchToInclination IS KSS:OBT:INCLINATION.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  OPEN LOOP FUNCTIONS                                                                                                   //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Calculates the launch azimuth for a "northerly" launch
LOCAL FUNCTION getLaunchAzimuth {

    // This IS what our launch azimuth WOULD be IF the planet weren't moving.
    LOCAL launchAzimuthInertial IS ARCSIN( COS(launchToInclination) / COS(SHIP:LATITUDE) ).

    // To compensate for the rotation of the planet, we need to estimate the orbital velocity we're going to gain during ascent. 
	// We can ballpark this by assuming a circular orbit at the targeted apoapsis, but there will necessarily be some 
	// very small error, which we will correct the closed-loop portion of our ascent.
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
LOCAL FUNCTION etaToOrbitPlane {
	PARAMETER is_AN,		// true = return the ETA for "northerly" launch
			  iter IS 1.

	LOCAL etaSecs IS -1.

	// The relative longitude measures the angular difference between the longitude of the launch site 
	// and the longitude of ascending node of an orbit described by the target orbital inclination
	LOCAL relativeLong IS ARCSIN(TAN(SHIP:LATITUDE)/TAN(launchToInclination)). 
    
	// IF the target orbit IS descending:
	IF NOT is_AN { SET relativeLong TO 180 - relativeLong. }

	// adjust for the geographic rotational variance from universal
	LOCAL targetLAN IS KSS:OBT:LAN.
    LOCAL geoLAN IS mAngle(targetLAN + relativeLong - BODY:ROTATIONANGLE).
    
	// get the angle between our current geographical longitude and the 
	// geographical longitude where the target orbital plane meets our latitude
	LOCAL node_angle IS mAngle(geoLAN - SHIP:LONGITUDE).
  
	// calculate how long the rotation of Kerbin will take to rotate us under the target orbit
	SET etaSecs TO ((node_angle / 360) * BODY:ROTATIONPERIOD). 
	
	// if we didn't find a good window in the first orbital period, keep looking
	IF iter > 1 SET etaSecs TO  etaSecs + (-BODY:ROTATIONPERIOD + (iter * BODY:ROTATIONPERIOD)).

  	RETURN etaSecs.
}

// call this to get the timestamp for the next acceptible launch window
// for now, this should get us very close to being on the same orbital plane as the KSS

// ideally we'd want to launch at the precise time when our circularization burn would 
// get us to within a few km below and behind the KSS at a low relative velocity
GLOBAL FUNCTION CalculateLaunchDetails {

	// fart in this general direction
	LOCAL laz IS getLaunchAzimuth().

	// the goal is to arrive in space as close to the KSS as possible, without going past the 
	// phase angle needed to intercept it with a Hohmann transfer within an acceptable period of time.
	
	LOCAL ascentTime IS 320.					// our ascent flight-time is pretty consistent
	LOCAL ascentDegs IS 20.0.					// and so is our downrange distance (degrees)
	LOCAL kssDPS IS 360 / KSS:OBT:PERIOD. 		// we know how fast the KSS is moving:
	LOCAL kssTravelDegs IS ascentTime * kssDPS.	// we can calculate how far the KSS will move (degrees) during our ascent

	// we need to subtract our distance travelled from that figure
	// we also need to take some out to ensure that we come up -behind- the KSS
	LOCAL maxPhase IS kssTravelDegs -ascentDegs -3.0.  
	LOCAL minPhase IS maxPhase -5.0.

	// maxPhase seems to be ~ 18 deg and min phase would thus be  ~13 deg with a 5 degree "window"

	// loop until we find the first suitable window.
	LOCAL etaSecs IS -1.
	LOCAL iter IS 1.
	LOCAL validWindow IS FALSE.

	UNTIL validWindow {
		// we prefer a northerly launch so check it first	
		LOCAL eta_to_AN IS etaToOrbitPlane(TRUE, iter).
		LOCAL anPA IS GetFuturePhaseAngle(TIME:SECONDS + eta_to_AN).
		
		IF anPA < maxPhase AND anPA > minPhase  {
			SET etaSecs TO eta_to_AN.
		
		} ELSE {
			// if that didn't work try again with a southerly launch
			LOCAL eta_to_DN IS etaToOrbitPlane(FALSE, iter).
			LOCAL dnPA IS GetFuturePhaseAngle(TIME:SECONDS + eta_to_DN).
			
			IF dnPA < maxPhase AND dnPA > minPhase {
				SET etaSecs TO eta_to_DN.
				SET laz TO mAngle(180 - laz).
			} ELSE {
				SET iter TO iter + 1.
			}
		}

		PRINT iter AT (20, 1).
		SET iter TO iter + 1.
		//SET validWindow TO etaSecs > 600.
		WAIT 0.2.
	}
		
	LOCAL launchTime IS TIMESTAMP(TIME:SECONDS + etaSecs - halfLaunchSecs).
	RETURN LIST(laz, launchTime).
}

// track when we first enter the pitch program so our initial pitch-over is very smooth
LOCAL pitchProgramStart IS 0.0.

// return the desired pitch based on given altitude
LOCAL FUNCTION pitchProgram {
	parameter shipAlt IS 0.0.
	
	IF pitchProgramStart = 0.0 SET pitchProgramStart TO shipAlt.
	IF shipAlt >= pitchProgramEndAltitude RETURN 0.0.
	
	RETURN MAX(0.0, 90 - 90 * ((shipAlt- pitchProgramStart) / pitchProgramEndAltitude) ^ pitchProgramExponent ).
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  CLOSED LOOP FUNCTIONS                                                                                                 //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


// This function returns an azimuth from a vector. 
// The azimuth can be used to create a navball heading.
LOCAL FUNCTION getAzimuth {

	//CLEARVECDRAWS().
		
	// 1 = get the normal vector of the target orbit:
	LOCAL tnv IS craftNormal(KSS, TIME).
	
	// 2 = Get the cross product of the target normal and your radius vector 
	// 3 = Normalize the result of the cross product 
	LOCAL rv IS posAt(SHIP, TIME).
	LOCAL cnorm IS VCRS(rv, tnv):NORMALIZED.

	// this gives you the unit vector you can construct a desired velocity vector from

	// 4 = Exclude the upvector from your orbital velocity vector.
	// 5 = Normalize the excluded vector, this is the basis for your current direction vector.
	LOCAL xNormed IS VXCL(SHIP:UP:VECTOR, SHIP:VELOCITY:ORBIT):NORMALIZED.

	// 6 = Multiply the vector from step 7 by the magnitude of your current orbital velocity.
	LOCAL curVector IS xNormed * SHIP:VELOCITY:ORBIT:MAG.

	// 7 = Calculate the orbital velocity required to reach your target AP given your current PE.
	LOCAL velAtAPO TO visVivaForDesiredFromCurrent().

	// 8 = Multiply the vector from step 3 by the result of step 4, this is your desired direction vector.
	// MAKE SURE that dirVector is always greater magnitude than curVector to avoid a nasty 180 deg flip:
	LOCAL dirVector IS cNorm * MAX(velAtAPO, curVector:MAG + 10).

	// 9 = Subtract the dirVector from the curVector; 
	// this vector gives you the direction along which you should point the vessel
	LOCAL fromVector IS dirVector - curVector.

	// 10 = convert the vector into an azimuth
	SET fromVector TO fromVector:NORMALIZED.

	LOCAL east IS vcrs(SHIP:UP:VECTOR, SHIP:NORTH:VECTOR).
	LOCAL trig_x IS vdot(SHIP:NORTH:VECTOR, fromVector).
	LOCAL trig_y IS vdot(east, fromVector).
	LOCAL result IS arctan2(trig_y, trig_x).

	IF result < 0 {
		SET result TO 360 + result.
	} 

	// 10 = apply some special sauce to actively steer more better
	// we can tell how far off we are from the target plane
	// by comparing the target normal vector and our radius vector
	LOCAL errAngle IS VANG(tnv, rv) -90.0.
		
	// show it on the UI
	SET planeError TO errAngle.	
		
	IF errAngle <> 0 {
		LOCAL corr IS max( min( errAngle * 10, 3 ), -3).
		SET result TO result - corr.
	}
	
	RETURN result.
}

// Calculate the orbital velocity required to reach your target AP given your current PE.
LOCAL FUNCTION visVivaForDesiredFromCurrent {
	// use the vis-viva equation:  v^2 = GM * (2/r - 1/a)
	LOCAL gm IS BODY:MU.
	LOCAL cr IS SHIP:ALTITUDE + BODY:RADIUS.
	LOCAL sma IS ((launchToApoapsis + SHIP:OBT:PERIAPSIS) / 2) + BODY:RADIUS.
	LOCAL velSq IS gm * (2/cr - 1/sma).
	RETURN SQRT(velSq).
}

// then, per iteration:
GLOBAL FUNCTION UpdateGuido {
	parameter shipAlt IS 0.0.
	
	LOCAL newPitch IS pitchProgram(shipAlt).
	
	// until we start using closed guidance just return the launchAzimuth
	LOCAL newAzimuth IS controlAzimuth.
	
	IF CLOSED_LOOP {
		// get guido to steer into the KSS orbital plane:
		SET newAzimuth TO getAzimuth().	
	} 

	SET GUIDO:AZIMUTH TO newAzimuth.
	SET GUIDO:PPROG TO newPitch.

}

GLOBAL FUNCTION GetRelativeInclination {
	parameter craft.
	RETURN craftRelInc(craft, TIME).
}


LOCAL FUNCTION GetFuturePhaseAngle {
	PARAMETER ts_AtTime.	// ut in seconds
			 
	// get position of KSS at that time
	LOCAL posKSS IS POSITIONAT(KSS, ts_AtTime) - POSITIONAT(BODY, ts_AtTime).
	LOCAL posKSS2 IS POSITIONAT(KSS, ts_AtTime + 10) - POSITIONAT(BODY, ts_AtTime + 10).
		
	// get geoposition of KSS at that time
	LOCAL geoKSS IS BODY:GEOPOSITIONOF(posKSS).
	LOCAL geoKSS2 IS BODY:GEOPOSITIONOF(posKSS2).
	
	// we know the geoposition of Woomerang
	LOCAL geoWoo IS LATLNG(45.29, 136.11).
	
	// get the great circle distance between these two points
	LOCAL dist IS GreatCircleDistance(geoKSS, geoWoo, BODY:RADIUS).
	LOCAL dist2 IS GreatCircleDistance(geoKSS2, geoWoo, BODY:RADIUS).
	
	IF dist2 - dist > 0 {		
		missionLog("moving away", ts_AtTime).
		RETURN 0.
	}
		
	// since we know the circumference of Kerbin we can convert this to degrees
	LOCAL circumf IS 2.0 * CONSTANT:PI * BODY:RADIUS.
	LOCAL fract IS dist / circumf.
	LOCAL degs IS 360 * fract.

	missionLog("degs: " + degs, ts_AtTime).

	// but how do we tell whether this distance is "ahead of" or "behind" the launch site?
	
	RETURN degs.

}


LOCAL FUNCTION GetPhaseAngle {

	LOCAL binormal IS VCRS(-BODY:POSITION:NORMALIZED, SHIP:VELOCITY:ORBIT:NORMALIZED):NORMALIZED.
	LOCAL phase IS VANG(-BODY:POSITION:NORMALIZED, VXCL(binormal, TARGET:POSITION - BODY:POSITION):NORMALIZED).
	LOCAL signVector IS VCRS(-BODY:POSITION:NORMALIZED, (TARGET:POSITION - BODY:POSITION):NORMALIZED).
	LOCAL sign IS VDOT(binormal, signVector).
	
    IF sign < 0 {
        // RETURN -phase. // if you want negative values to represent "the target is behind the ship" in orbit
		RETURN 360 - phase.  // if you want this to be an absolute value of far ahead of your ship is the target
    }
    ELSE {
        RETURN phase.
    }

}

