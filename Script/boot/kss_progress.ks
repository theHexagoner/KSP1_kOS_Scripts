@LAZYGLOBAL OFF.

// put at the top of most boot files:
PRINT "Bootloader loading...".
WAIT UNTIL SHIP:UNPACKED.

//
// .. The rest of your boot file goes here ..
//
// PRELAUNCH, SUB_ORBITAL, ORBITING and DOCKED.


// ARE WE STILL HERE?

if SHIP:STATUS = "PRELAUNCH" {

	SWITCH TO 0.

	PRINT "Copying libraries...".
	COPYPATH("common", "1:").  // for now just copy everything

	PRINT "Copying mission...".
	COPYPATH("craft/progress/m_launch_to_kss.ks", "1:/").
	COPYPATH("craft/progress/m_rendezvous_kss.ks", "1:/").
	COPYPATH("craft/progress/ui_flightstate.ks", "1:/").	
	COPYPATH("craft/progress/spacecraft.ks", "1:/").
	COPYPATH("craft/progress/guido.ks", "1:/").
	COPYPATH("craft/progress/m_dock_kss.ks", "1:/").

	WAIT 0.5.
	PRINT "kOS boot complete...".

	SWITCH TO 1.
	RUNONCEPATH("m_launch_to_kss.ks").

}

// ARE WE THERE YET?
IF SHIP:STATUS = "SUB_ORBITAL" {
	
	// check to see if re-entry files have been uploaded
	// if we are not on our way to planned re-entry 
	// load and run the rendezvous scripts
	// otherwise execute re-entry

	SWITCH TO 1.
	RUNONCEPATH("m_rendezvous_kss.ks").
	
}

// ARE WE THERE YET?
IF SHIP:STATUS = "ORBITING" {

	// in the happy-path, we have completed rendezvous with KSS
	// if so load and run the docking scripts

	// but if we are not yet in rendezvous, resume that script instead

}

// WHEN ARE WE LEAVING?
IF SHIP:STATUS = "DOCKED" {

	// we are waiting to leave
	// load the re-entry scripts

	// user will initiate these somehow?

}

// any other status would be invalid
PRINT "UNRECOVERABLE BOOT ERROR.".
PRINT "SHUTTING DOWN.".
PRINT 1/0.



