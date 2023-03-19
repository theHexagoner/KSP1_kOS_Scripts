@LAZYGLOBAL OFF.

// put at the top of most boot files:
PRINT "Bootloader loading...".
WAIT UNTIL SHIP:UNPACKED.

//
// .. The rest of your boot file goes here ..
//

// ARE WE STILL HERE?

if SHIP:STATUS = "PRELAUNCH" {

	// is it day or night?
	IF SHIP:SENSORS:LIGHT >= 0.85 {
		// turn off the lights
		LIGHTS OFF.
		
	} ELSE {
		// turn on the lights
		LIGHTS ON.
	}

	SWITCH TO 0.

	PRINT "Copying libraries...".
	IF EXISTS("common") COPYPATH("common", "1:").  // for now just copy everything

	PRINT "Copying mission...".
	IF EXISTS("progress") COPYPATH("progress", "1:"). // all the mission specific programs are here

	SWITCH TO 1.
	IF EXISTS("progress") CD("progress").
	WAIT 2.0.
	PRINT "kOS boot complete...".

	RUN interceptkss.

}