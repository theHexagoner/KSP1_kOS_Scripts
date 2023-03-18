@LAZYGLOBAL OFF.

RUNONCEPATH("../common/lib_common.ks").

global CLOSED_LOOP is FALSE.

// how high is up?
global launchToApoapsis is 115000.0. // m

// The pitch program end altitude is the altitude, in meters, at which we level out to a pitch of 0° off the horizontal.
// this seems to be more or less constrained to the top of the atmosphere when using the sqrt solution for controlling pitch
global pitchProgramEndAltitude is 91500.0.  // meters

// show some stuff in the console when we get into the active guidance
global velAtAPO is 0.0.

// this should be 1/2 the duration (in seconds) of the ascent burn (all stages)
// used to predict launch window for intercepting the KSS orbit
local halfLaunchSecs is 160.0.

// This parameter controls the shape of the ascent curve.
local pitchProgramExponent is  0.45.


// We are launching at the KSS, which is generally in an orbit inclined to 51.6 deg
local launchToInclination is KSS:OBT:INCLINATION.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  OPEN LOOP FUNCTIONS                                                                                                   //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Calculates the launch azimuth for a "northerly" launch
local function getLaunchAzimuth {

    // This is what our launch azimuth WOULD be if the planet weren't moving.
    local launchAzimuthInertial is ARCSIN( COS(launchToInclination) / COS(SHIP:LATITUDE) ).

    // To compensate for the rotation of the planet, we need to estimate the orbital velocity we're going to gain during ascent. 
	// We can ballpark this by assuming a circular orbit at the pitch program end altitude, but there will necessarily be some 
	// very small error, which we will correct the closed-loop portion of our ascent.
    local vApproximate is SQRT( SHIP:BODY:MU / ( SHIP:BODY:RADIUS + pitchProgramEndAltitude ) ).

    // Construct the components of the launch vector in the rotating frame. 
	// NOTE: In this frame the x axis points north and the y axis points east because KSP
    local x is vApproximate * COS(launchAzimuthInertial).
    local y is vApproximate * SIN(launchAzimuthInertial) - SHIP:VELOCITY:ORBIT:MAG * COS(SHIP:LATITUDE).

    // Finally, the launch azimuth is the angle of the launch vector we just computed, measured from the x (north) axis: 
    return ARCTAN2(y, x).
}

// Calculates the estimated time (in seconds) until the orbital plane described by the LAN and inclination
// of the target orbital plan will pass over the ship's location
local function etaToOrbitPlane {
	PARAMETER is_AN.		// true = return ETA for "northerly" launch
	local etaSecs is -1.

	// The relative longitude measures the angular difference between the longitude of the launch site 
	// and the longitude of ascending node of an orbit described by the target orbital inclination
	local relativeLong is ARCSIN(TAN(SHIP:LATITUDE)/TAN(launchToInclination)). 
    
	// if the target orbit is descending:
	if NOT is_AN { set relativeLong to 180 - relativeLong. }

	// adjust for the geographic rotational variance from universal
	local targetLAN is KSS:OBT:LAN.
    local geoLAN is mAngle(targetLAN + relativeLong - BODY:ROTATIONANGLE).
    
	// get the angle between our current geographical longitude and the 
	// geographical longitude where the target orbital plane meets our latitude
	local node_angle is mAngle(geoLAN - SHIP:LONGITUDE).
  
	// calculate how long the rotation of Kerbin will take to rotate us under the target orbit
	set etaSecs to (node_angle / 360) * BODY:ROTATIONPERIOD.

  	return etaSecs.
}

// call this to get the timestamp for the next acceptible launch window
// for now, this should get us very close to being on the same orbital plane as the KSS

// ideally we'd want to launch at the precise time when our circularization burn would 
// get us to within a few km below and behind the KSS at a low relative velocity

global function CalculateLaunchDetails {
	local eta_to_AN is etaToOrbitPlane(TRUE).
	local eta_to_DN is etaToOrbitPlane(FALSE).
	local laz is getLaunchAzimuth().
		
	local etaSecs is -1.
	
	// figure out the earliest viable option
	if (eta_to_DN < eta_to_AN OR eta_to_AN < halfLaunchSecs) AND eta_to_DN >= halfLaunchSecs {
		// the DN comes first OR 
		// the AN happens first but sooner than we can launch in time
		// in either of these cases the DN does not arrive sooner than we can launch
		set etaSecs to eta_to_DN.
		set laz to mAngle(180 - laz).  

	} ELSE if eta_to_AN >= halfLaunchSecs {
		// the AN happens first, and in time for us to launch
		set etaSecs to eta_to_AN. 

	} ELSE { 
		// how does it get here?
		set etaSecs to eta_to_AN + BODY:ROTATIONPERIOD. 
	}
		
	local launchTime is TIMESTAMP(TIME:SECONDS + etaSecs - halfLaunchSecs).
	return LIST(laz, launchTime).
}


// return the desired pitch based on given altitude
local function pitchProgram {
	parameter shipAlt is 0.0.
	return MAX(0.0, 90.0 - 90.0 * (shipAlt / pitchProgramEndAltitude) ^ pitchProgramExponent).
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  CLOSED LOOP FUNCTIONS                                                                                                 //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// This function returns an azimuth from a vector. 
// The azimuth can be used to create a navball heading.
local function getAzimuth {
	parameter fromVector.
	
	set fromVector to fromVector:NORMALIZED.

	local east is vcrs(SHIP:UP:VECTOR, SHIP:NORTH:VECTOR).

	local trig_x is vdot(SHIP:NORTH:VECTOR, fromVector).
	local trig_y is vdot(east, fromVector).

	local result is arctan2(trig_y, trig_x).

	if result < 0 {
		return 360 + result.
	} else {
		return result.
	}
}

// calculates a vector based on which way we're heading and which 
// way we need to turn to get into a matching orbital plane
local function calculateDirectionalVector {

	// 1 = get the normal vector of the target orbit:
	local tnv is craftNormal(KSS, TIME).

	// 2 = Get the cross product of the target normal and your radius vector 
	// 3 = Normalize the result of the cross product 
	local rv is posAt(SHIP, TIME).
	local cnorm is VCRS(rv, tnv):NORMALIZED.

	// this gives you the unit vector you can construct a desired velocity vector from

	// 4 = Calculate the orbital velocity required to reach your target AP given your current PE.
	set velAtAPO to visVivaForDesiredFromCurrent().

	// 5 = Multiply the vector from step 3 by the result of step 4, this is your desired direction vector.
	local dirVector is cNorm * velAtAPO.

	// 6 = Exclude the upvector from your orbital velocity vector.
	// 7 = Normalize the excluded vector, this is the basis for your current direction vector.
	local xNormed is VXCL(SHIP:UP:VECTOR, SHIP:VELOCITY:ORBIT):NORMALIZED.

	// 8 = Multiply the vector from step 7 by the magnitude of your current orbital velocity.
	local curVector is xNormed * SHIP:VELOCITY:ORBIT:MAG.

	// 9 = Subtract the vector resulting from step 8 from the vector resulting from step 5, 
	// this vector gives you the direction along which you should point the vessel
	local vForDir is dirVector - curVector.

	return vForDir.
}

// Calculate the orbital velocity required to reach your target AP given your current PE.
local function visVivaForDesiredFromCurrent {
	// use the vis-viva equation:  v^2 = GM * (2/r - 1/a)
	local gm is BODY:MU.
	local cr is SHIP:ALTITUDE + BODY:RADIUS.
	local sma is ((launchToApoapsis + SHIP:OBT:PERIAPSIS) / 2) + BODY:RADIUS.
	local velSq is gm * (2/cr - 1/sma).
	return SQRT(velSq).
}

// then, per iteration:
global function Guido {
	parameter shipAlt is 0.0.
	
	local results is LEXICON().
	local newPitch is pitchProgram(shipAlt).
	
	// until we start using closed guidance just return the launchAzimuth
	local newAzimuth is controlAzimuth.
	
	if CLOSED_LOOP {
		// get guido to steer into the KSS orbital plane:
		local vForDir is calculateDirectionalVector().	
		set newAzimuth to getAzimuth(vForDir).	
	} else {
		set velAtAPO to visVivaForDesiredFromCurrent().
	}

	results:ADD("Azimuth", newAzimuth).
	results:ADD("Pitch", newPitch).

	return results.
}

global function GetRelativeInclination {
	parameter craft.
	return craftRelInc(craft, TIME).
}



