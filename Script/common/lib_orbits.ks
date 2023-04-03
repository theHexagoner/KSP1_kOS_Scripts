


// ORBITAL STUFF ////////////////////////////////////////////////////////////////////////////////////////////////////////////

// get orbital velocity of a vessel at a given time
GLOBAL FUNCTION velAt {
	PARAMETER craft, 
			  u_time.

	RETURN VELOCITYAT(craft,u_time):ORBIT.
}

// get the radius vector for a vessel at a given time
GLOBAL FUNCTION posAt {
	PARAMETER craft, 
			  u_time.

	LOCAL b IS ORBITAT(craft, u_time):BODY.
	LOCAL p IS POSITIONAT(craft, u_time).
	IF b <> BODY { 
		SET p TO p - POSITIONAT(b, u_time). 
	} ELSE { 
		SET p TO p - BODY:POSITION. 
	}

	RETURN p.
}

// get the "normal vector" for a vessel/orbit at a given time
GLOBAL FUNCTION craftNormal {
	PARAMETER craft, 
			  u_time.
	
	RETURN VCRS(velAt(craft, u_time), posAt(craft, u_time)).
}

// get the relative inclincation between the SHIP and another vessel at given time
GLOBAL FUNCTION craftRelInc {
	PARAMETER craft, 
			  u_time.
	
	RETURN VANG(craftNormal(SHIP, u_time), craftNormal(craft, u_time)).
}


GLOBAL FUNCTION orbitNormal
{
    PARAMETER planet, 
  			  incline, 
  			  o_Lan.
    
    LOCAL o_pos IS R(0,-o_Lan,0) * SOLARPRIMEVECTOR:NORMALIZED.
    LOCAL o_vec IS ANGLEAXIS(-incline,o_pos) * VCRS(planet:ANGULARVEL,o_pos):NORMALIZED.
    RETURN VCRS(o_vec,o_pos).
}

GLOBAL FUNCTION orbitRelInc
{
   PARAMETER u_time, 
			 incline, 
			 o_Lan.
			 
   RETURN VANG(craftNormal(SHIP,u_time), orbitNormal(ORBITAT(SHIP,u_time):BODY,incline,o_Lan)).
}

// get an SMA for an arbitrary orbit, giving no params is same as SHIP:ORBIT:SEMIMAJORAXIS
GLOBAL FUNCTION getSMA {
	PARAMETER ap IS SHIP:APOAPSIS,
			  pe IS SHIP:PERIAPSIS,
			  ra IS SHIP:BODY:RADIUS.
				
	RETURN ra + ((pe + ap) / 2).
}