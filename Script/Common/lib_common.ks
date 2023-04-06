@LAZYGLOBAL OFF.

// normalize an angle between 0 and 360
GLOBAL FUNCTION mAngle
{
	PARAMETER angle.
	UNTIL angle >= 0 { SET angle TO angle + 360. }
	RETURN MOD(angle, 360).
}


// from KS LIB
//use to find the distance from...
GLOBAL FUNCTION GreatCircleDistance {
	PARAMETER p1,     //...this point...
			  p2,     //...to this point...
              radius. //...around a body of this radius (maybe add altitude if you are flying?)
 
	LOCAL A IS SIN((p1:lat-p2:lat)/2)^2 + COS(p1:lat)*COS(p2:lat)*SIN((p1:lng-p2:lng)/2)^2.
	RETURN radius*CONSTANT():PI*ARCTAN2(SQRT(A),SQRT(1-A))/90.
}.

// courtesy of u/JitteryJet
// Calculates the position vector of the spot above (or below) a geographical coordinate at some time in the future.
GLOBAL FUNCTION CalcGeoPositionAt {
    PARAMETER geo,			// geoposition
			  ts_AtTime.	// seconds from epoch
			  
	LOCAL duration IS ts_AtTime - TIME:SECONDS. // how long we twist
	LOCAL diff IS (duration / BODY:ROTATIONPERIOD) * 360.
		
    LOCAL futureLong IS geo:LNG + diff. 
	LOCAL futureR IS LATLNG(geo:LAT, futureLong):POSITION.
    RETURN futureR.
}