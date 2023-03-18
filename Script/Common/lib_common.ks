@LAZYGLOBAL OFF.

// normalize an angle between 0 and 360
global function mAngle
{
	parameter angle.
	until angle >= 0 { set angle to angle + 360. }
	return MOD(angle, 360).
}

// get an SMA, if you just give the AP it will assume a circular orbit around the SHIP:BODY
global function getSMA {
	parameter ap is SHIP:APOAPSIS,
			  pe is ap,
			  ra IS SHIP:BODY:RADIUS.
				
	return ra + ((pe + ap) / 2).
}


// VECTOR STUFF ////////////////////////////////////////////////////////////////////////////////////////////////////////////

// get orbital velocity of a vessel at a given time
global function velAt {
	parameter craft, 
			  u_time.

	return VELOCITYAT(craft,u_time):ORBIT.
}

// get the radius vector for a vessel at a given time
global function posAt {
	parameter craft, 
			  u_time.

	local b IS ORBITAT(craft, u_time):BODY.
	local p IS POSITIONAT(craft, u_time).
	if b <> BODY { 
		set p to p - POSITIONAT(b, u_time). 
	} else { 
		set p to p - BODY:POSITION. 
	}

	return p.
}

// get the "normal vector" for a vessel/orbit at a given time
global function craftNormal {
	parameter craft, 
			  u_time.
	
	return VCRS(velAt(craft, u_time), posAt(craft, u_time)).
}

// get the relative inclincation between the SHIP and another vessel at given time
global function craftRelInc {
	parameter craft, 
			  u_time.
	
	return VANG(craftNormal(SHIP, u_time), craftNormal(craft, u_time)).
}


// STRING FORMATTING ///////////////////////////////////////////////////////////////////////////////////////////////////////

// This function turns a number into a string representation with a fixed number of digits after the decimal point. 
// For example, RoundZero(1.6, 2) returns "1.60" with that extra zero as padding.
global function RoundZero {
    declare PARAMETER n.
    declare PARAMETER desiredPlaces is 0.

    local str is ROUND(n, desiredPlaces):TOSTRING.

    if desiredPlaces > 0 {
        local hasPlaces is 0.
        if str:CONTAINS(".") {
            set hasPlaces to str:LENGTH - str:FIND(".") - 1.
        } ELSE {
            set str to str + ".".
        }
        if hasPlaces < desiredPlaces {
            FROM { local i is 0. } until i = desiredPlaces - hasPlaces STEP { set i to i + 1. } DO {
                set str to str + "0".
            }
        }
    }

    return str.
}

// you guessed it  
// 0y 0d 0h 0m 0s
global function FormatTimespan {
	parameter span.

	local yy is span:YEAR:TOSTRING:PADLEFT(2):REPLACE(" ", "0") + "y".
	local dd is span:DAY:TOSTRING:PADLEFT(2):REPLACE(" ", "0") + "d".
	local hh is span:HOUR:TOSTRING:PADLEFT(2):REPLACE(" ", "0") + "h".
	local mm is span:MINUTE:TOSTRING:PADLEFT(2):REPLACE(" ", "0") + "m".
	local ss is span:SECOND:TOSTRING:PADLEFT(2):REPLACE(" ", "0") + "s".

	local fstr is ss.
	
	if span:MINUTE > 0 set fstr to mm + " " + fstr.
	if span:DAY > 0 set fstr to dd + " " + fstr.
	if span:YEAR > 0 set fstr to yy + " " + fstr.

	return fstr:PADLEFT(12).  //  0y 0d 0h 0m 0s
}



