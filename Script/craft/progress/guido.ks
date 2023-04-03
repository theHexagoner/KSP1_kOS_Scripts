
// this program contains utility functions for steering a Progress spacecraft through various
// problems of orbital mechanics towards a rendezvous with the KSS

RUNONCEPATH("/common/lib_orbits.ks").


// shortcut for getting relative inclination
GLOBAL FUNCTION GetRelativeInclinationToKSS {
	RETURN craftRelInc(theKSS, TIME).
}




////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  Closest approach functions                                                                                            //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// how to use
// LOCAL timeUntilClosest IS GetETA_ClosestApproachToKss().
// LOCAL distanceAtClosest IS (posAt(KSS, timeUntilClosest) - posAt(SHIP, timeUntilClosest)):MAG.


// derived from RAMP
// Determine the time of closest approach to KSS (ETA in seconds)
// After the Hohmann transfer, we know it will be in a very short slice of time when the osculating orbital positions
// of our ship and the KSS are approximately 180 degrees from the start of the transfer burn
GLOBAL FUNCTION GetETA_ClosestApproachToKss {
	PARAMETER tMin IS TIME:SECONDS,   						// define a time span to look for closest approach
			  tMax IS Tmin + 2 * MAX(SHIP:OBT:PERIOD, theKSS:OBT:PERIOD). // from now until 2 orbits?
	
	LOCAL Tmin IS TIME:SECONDS.
	LOCAL Tmax IS Tmin + 2 * MAX(SHIP:OBT:PERIOD, theKSS:OBT:PERIOD).

	UNTIL Tmax - Tmin < 5 {
		LOCAL dt2 IS (Tmax - Tmin) / 2.
		LOCAL Rl IS findCloseApproach(Tmin, Tmin + dt2).
		LOCAL Rh IS findCloseApproach(Tmin + dt2, Tmax).
		IF Rl < Rh {
			SET Tmax TO Tmin + dt2.
		} ELSE {
			SET Tmin TO Tmin + dt2.
		}
	}

	RETURN (Tmax + Tmin) / 2.
}

// derived from RAMP
// Given that the SHIP "passes" KSS during time span, find the APPROXIMATE
// distance of closest approach.. Use this iteratively to find the true closest approach.
LOCAL FUNCTION findCloseApproach {
	PARAMETER Tmin.
	PARAMETER Tmax.

	LOCAL rBest IS (SHIP:POSITION - theKSS:POSITION):MAG.
	LOCAL dt IS (Tmax - Tmin) / 32.

	LOCAL T IS Tmin.
	UNTIL T >= Tmax {
		LOCAL p IS (positionAt(SHIP, T)) - (positionAt(theKSS, T)).
		if p:MAG < rBest {
			set rBest to p:MAG.
		}
		set T to T + dt.
	}

	return rBest.
}

// derived from RAMP
// get the distance in meters at time of closest approach
GLOBAL FUNCTION GetClosestApproachToKss {
	PARAMETER etaToClosest.
	LOCAL timeAtClosest TO TIMESTAMP(TIME:SECONDS + etaToClosest).
	RETURN (posAt(theKSS, timeAtClosest) - posAt(SHIP, timeAtClosest)):MAG.	
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  match inclination maneuver, in case you didn't get close enough during ascent
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// derived from RAMP:
// create a node for matching inclination with KSS
GLOBAL FUNCTION GetInclinationNode {
	
	local ta is 0. // TRUE ANOMALY = angle from periapsis to DN
	local t0 is TIME:SECONDS.

	LOCAL rv IS posAt(SHIP, TIME).
	LOCAL snv IS craftNormal(SHIP, TIME). // normal vector of SHIP
	LOCAL tnv IS craftNormal(theKSS, TIME). // normal vector of KSS
	
	LOCAL lineOfNodes IS VCRS(tnv, snv). // the line from AN to DN
	
	// relative inlination?
	LOCAL di IS VANG(snv, tnv). // inclination difference (target-current)

	// start figuring out the true anomaly
	// get the angle in degrees, we are from the line of nodes
	LOCAL ta IS VANG(rv, lineOfNodes).
	
	// fix sign by comparing cross-product to normal vector (the angle is either 0 or 180)
	IF VANG(VCRS(rv, lineOfNodes), snv) < 90 SET ta TO -ta.

	SET ta TO ta + ORBIT:TRUEANOMALY.
	SET ta TO utilAngleTo360(ta).
	
	// figure out if we are going to burn at AN or DN?
	IF ta < ORBIT:TRUEANOMALY { 
		SET ta TO ta + 180. 
		SET di TO -di. 
	}
	
	// get time until ta
	LOCAL dt IS utilDtTrue(ta).
	LOCAL t1 IS t0 + dt.

	LOCAL vat IS velAt(ship, t1):MAG.
	
	LOCAL nv IS vat * SIN(di).
	LOCAL pv IS vat *(COS(di) - 1).

	// FIXME: nv + pv for highly eccentric orbits

	RETURN NODE(t1, 0, nv, pv).

}

// TODO: there are many ways to do this, please pick ONE
// convert any angle to range [0, 360)
LOCAL FUNCTION utilAngleTo360 {
	PARAMETER pAngle.
	SET pAngle TO MOD(pAngle, 360).
	IF pAngle < 0 SET pAngle TO pAngle + 360.
	RETURN pAngle.
}

// https://en.wikipedia.org/wiki/Eccentric_anomaly
// https://en.wikipedia.org/wiki/Mean_anomaly

// convert from true to mean anomaly
LOCAL FUNCTION utilMeanFromTrue {
	PARAMETER pAnomaly.
	PARAMETER pOrbit is orbit.
	
	LOCAL ecc is pOrbit:ECCENTRICITY.
	
	IF ecc < 0.001 RETURN pAnomaly. // circular, no need for conversion

	IF ecc >= 1 { 
		PRINT "ERROR: meanFromTrue(" + ROUND(pAnomaly, 2) + ") with ecc = " + ROUND(ecc, 5). 
		RETURN pAnomaly.
	}
	
	SET pAnomaly TO pAnomaly * 0.5.
	SET pAnomaly TO 2 * ARCTAN2( SQRT( 1 - ecc ) * SIN( pAnomaly ), SQRT(1 + ecc) * COS(pAnomaly)).
	
	RETURN pAnomaly - ecc * SIN(pAnomaly) * 180 / CONSTANT:PI.
}

// get ETA to true anomaly (angle from periapsis in the direction of movement)
// note: this is the ultimate ETA function which is in KSP API known as GetDTforTrueAnomaly
LOCAL FUNCTION utilDtTrue {
	PARAMETER pAnomaly.
	PARAMETER pOrbit IS ORBIT.
	RETURN utilAngleTo360(utilMeanFromTrue(pAnomaly) - utilMeanFromTrue(pOrbit:TRUEANOMALY)) / 360 * pOrbit:PERIOD.
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  Phase Angle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// derived from ksLib
// get the phase angle between SHIP and KSS
GLOBAL FUNCTION GetPhaseAngleToKSS {

	LOCAL binormal IS VCRS(-KERBIN:POSITION:NORMALIZED, SHIP:VELOCITY:ORBIT:NORMALIZED):NORMALIZED.
	LOCAL phase IS VANG(-KERBIN:POSITION:NORMALIZED, VXCL(binormal, theKSS:POSITION - KERBIN:POSITION):NORMALIZED).
	LOCAL signVector IS VCRS(-KERBIN:POSITION:NORMALIZED, (theKSS:POSITION - KERBIN:POSITION):NORMALIZED).
	LOCAL sign IS VDOT(binormal, signVector).

	
    IF sign < 0 {
        // RETURN -phase. // if you want negative values to represent "the KSS is behind the ship" in orbit
		RETURN 360 - phase.  // if you want this to be an absolute value of far ahead of your ship is the KSS
    }
    ELSE {
        RETURN phase.
    }

}




