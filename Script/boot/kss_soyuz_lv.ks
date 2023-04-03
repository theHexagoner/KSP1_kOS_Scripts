@LAZYGLOBAL OFF.

// put at the top of most boot files:
PRINT "Soyuz LV KSS Mission".
PRINT "Bootloader loading...".
WAIT UNTIL SHIP:UNPACKED.

//
// .. The rest of your boot file goes here ..
//
// PRELAUNCH, FLIGHT, SUB_ORBITAL, ORBITING


// ARE WE STILL HERE?

IF SHIP:STATUS = "PRELAUNCH" {
	
	// give other CPUs time to come online
	WAIT 3.0.

	// IS it day or night?
	IF SHIP:SENSORS:LIGHT >= 0.85 {
		// turn off the lights
		LIGHTS OFF.
		
	} ELSE {
		// turn on the lights
		LIGHTS ON.
	}

	SWITCH TO 0.

	PRINT "Copying libraries...".
	COPYPATH("common", "1:").  // for now just copy everything

	PRINT "Copying mission...".
	COPYPATH("lvs/soyuz/launchpad.ks", "1:/").
	COPYPATH("lvs/soyuz/lift_vehicle.ks", "1:/").
	COPYPATH("lvs/soyuz/S3.ks", "1:/").
	COPYPATH("lvs/soyuz/m_abort.ks", "1:/").
	COPYPATH("lvs/soyuz/guido.ks", "1:/").
	COPYPATH("lvs/soyuz/ui_flightState.ks", "1:/").
	COPYPATH("lvs/soyuz/m_launch_to_kss.ks", "1:/").	

	WAIT 0.5.
	PRINT "kOS boot complete...".

	SWITCH TO 1.
	RUNONCEPATH("m_launch_to_kss.ks").

}

// IF we somehow boot into any other STATUS, it's probably a mission fail

IF SHIP:STATUS = "FLIGHT" OR
   SHIP:STATUS = "SUB_ORBITAL" OR
   SHIP:STATUS = "ORBITING" {

	// somebody will push the big red button
	WAIT UNTIL NOT CORE:MESSAGES:EMPTY.
	SET RECEIVED TO CORE:MESSAGES:POP.

	IF RECEIVED:CONTENT = "SELF DESTRUCT" {
		PRINT "GOOD BYE!".
		SWITCH TO 1.
		RUNONCEPATH("m_abort.ks").

	} ELSE {
		PRINT "Unexpected message: " + RECEIVED:CONTENT.
	}
}


// IF we somehow are landed or splashed, somebody will recover us
// any other status would be invalid
PRINT "UNRECOVERABLE BOOT ERROR.".
PRINT "SHUTTING DOWN.".
PRINT 1/0.
