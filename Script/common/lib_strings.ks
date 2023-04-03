
// STRING FORMATTING ///////////////////////////////////////////////////////////////////////////////////////////////////////

// This function turns a number into a string representation with a fixed number of digits after the decimal point. 
// For example, RoundZero(1.6, 2) returns "1.60" with that extra zero as padding.
GLOBAL FUNCTION RoundZero {
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

// you guessed it  
// 0y 0d 0h 0m 0s
GLOBAL FUNCTION FormatTimespan {
	PARAMETER span.

	LOCAL yy IS span:YEAR:TOSTRING:PADLEFT(2):REPLACE(" ", "0") + "y".
	LOCAL dd IS span:DAY:TOSTRING:PADLEFT(2):REPLACE(" ", "0") + "d".
	LOCAL hh IS span:HOUR:TOSTRING:PADLEFT(2):REPLACE(" ", "0") + "h".
	LOCAL mm IS span:MINUTE:TOSTRING:PADLEFT(2):REPLACE(" ", "0") + "m".
	LOCAL ss IS span:SECOND:TOSTRING:PADLEFT(2):REPLACE(" ", "0") + "s".

	LOCAL fstr IS ss.
	
	IF span:MINUTE > 0 SET fstr TO mm + " " + fstr.
	IF span:DAY > 0 SET fstr TO dd + " " + fstr.
	IF span:YEAR > 0 SET fstr TO yy + " " + fstr.

	RETURN fstr:PADLEFT(12).  //  0y 0d 0h 0m 0s
}


