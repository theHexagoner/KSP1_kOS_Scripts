@LAZYGLOBAL OFF.
ABORT OFF.
SAS OFF.
RCS OFF.

// Example Mission Script for the Making History "Acapello" Mun lander.
// derived from KSProgramming video series by Cheers Kevin Games

SET CONFIG:IPU TO 2000.0.

LOCAL TARGET_MUNAR_ALTITUDE IS 50000.

LOCAL mission IS Import("mission").
LOCAL tranzfer IS Import("transfer").
LOCAL descent IS Import("descent").
LOCAL launch IS Import("launch").
LOCAL rsvp IS Import("rsvp/main").

LOCAL freeze IS tranzfer["Freeze"].

LOCAL nextBurntime IS 0.
LOCAL launchAzimuth IS 270.
LOCAL launchETA IS 0.

LOCAL m_lm IS mission( { 
	PARAMETER seq, 		// mission sequence
			  evts,  	// mission events
			  goNext. 	// what happens next

	// are we there yet?
	seq:ADD ( {
		IF BODY = Mun AND SHIP:OBT:ECCENTRICITY < 1.0 {
			
			SET TARGET_MUNAR_ALTITUDE TO SHIP:APOAPSIS.
			
			// turn on the power:
			LOCAL theLM TO SHIP:PARTSTAGGED("theLM")[0].
			FOR rs IN theLM:RESOURCES {
				IF rs:NAME = "ELECTRICCHARGE" rs:ENABLED ON.
				IF rs:NAME = "MONOPROPELLANT" rs:ENABLED ON.
				IF rs:NAME = "LIQUIDFUEL" rs:ENABLED OFF.
				IF rs:NAME = "OXIDIZER" rs:ENABLED OFF.
			}
			
			WAIT 1.0.
		
			goNext().
		}
	}).

	// wait for the LM to separate from the CM
	seq:ADD( { 
		IF SHIP:CREW():LENGTH = 2 { 
			SET STEERINGMANAGER:MAXSTOPPINGTIME TO 0.1.
			LOCK STEERING TO SHIP:PROGRADE.			
			WAIT 5.
			goNext().
		}
	}).
	
	// move away from the CM
	seq:ADD( {
		SET theCM TO VESSEL("Acapella").

		// puff out some RCS and move away at 1 m/s
		SAS OFF.		
		RCS ON.

		SET SHIP:CONTROL:FORE TO -0.1.
		UNTIL (SHIP:VELOCITY:ORBIT - theCM:VELOCITY:ORBIT):MAG > 1.0 WAIT 0.
		SET SHIP:CONTROL:FORE TO 0.1.
		UNTIL (SHIP:VELOCITY:ORBIT - theCM:VELOCITY:ORBIT):MAG <= 0.1 WAIT 0.
		SET SHIP:CONTROL:FORE TO 0.0.
		
		// make sure we have cleared the CM
		UNTIL theCM:DISTANCE > 15.0 WAIT 0.
		PRINT "Jeb: We're away, now translating".
		WAIT 2.

		// also translate radial-in at 1 m/s to clear the CM
		SET SHIP:CONTROL:TOP TO -0.1.
		UNTIL (SHIP:VELOCITY:ORBIT - theCM:VELOCITY:ORBIT):MAG > 1.0 WAIT 0.
		SET SHIP:CONTROL:TOP TO 0.0.

		PRINT "Jeb: Waiting to clear the CM".

		// when we are 50m from the CM
		UNTIL theCM:DISTANCE > 49.0 WAIT 0.
		PRINT "Jeb: Cleared the CM".
		RCS OFF.
		WAIT 1.
		
		goNext().
	}).
	
	// transfer to a low ~ 15km orbit PE
	seq:ADD( {
		
		LOCK THROTTLE TO 0.
		LOCK STEERING TO LOOKDIRUP(SHIP:RETROGRADE:VECTOR, -SHIP:UP:VECTOR).
		WAIT 10.
		
		//activate descent engine
		LOCAL d_engine IS SHIP:PARTSTAGGED("DESCENT_E")[0].
		d_engine:ACTIVATE().
		
		// calculate a burn time to get us from AP to desired PE?
		// wait until we are at the correct burntime?
		// do the burn?
		
		// close 'nuff
		PRINT "Commencing RETRO".
		WAIT 1.

		LOCK THROTTLE TO 1.
		UNTIL SHIP:OBT:PERIAPSIS <= 15000.0 {
			LOCAL T IS MAX(1.0 - (15000.0 / SHIP:OBT:PERIAPSIS), 0.01).
			LOCK THROTTLE TO T.
			WAIT 0.
		}
		LOCK THROTTLE TO 0.
		
		PRINT "RETRO complete".
		goNext().
	}).
	
	// if we are in daylight and have comms with Kerbin?
	
	// circularize the low orbit
	seq:ADD( {

		PRINT "Bob: calculating RETRO2".
		LOCK THROTTLE TO 0.
		LOCK STEERING TO LOOKDIRUP(SHIP:RETROGRADE:VECTOR, -SHIP:UP:VECTOR).
		WAIT 10.
		
		// calculate burn to circularize at desired altitude
		tranzfer:Node_For_AP(SHIP:OBT:PERIAPSIS).

		// do the burn
		tranzfer["Exec"]().
		
		LOCK THROTTLE TO 0.
				
		PRINT "Jeb: RETRO2 complete".
		
		goNext().
	}).
	
	// deorbit
	seq:ADD( {
	
		LOCK THROTTLE TO 0.
		LOCK STEERING TO LOOKDIRUP(SHIP:RETROGRADE:VECTOR, -SHIP:UP:VECTOR).
		
		//TODO: wait until we are opposite from Kerbin?
		WAIT 30.
		
		PRINT "Bob: Prepare for deorbit burn".
		WAIT 5.
	
		descent["Deorbit_Burn"]().

		LOCK THROTTLE TO 0.
		WAIT 1.
		

		goNext().
	}).

	// calculate and perform the braking burn
	seq:ADD( { 
		
		// the calculating takes a lot of juice
		FUELCELLS ON.
		
		LOCAL d_engine IS SHIP:PARTSTAGGED("DESCENT_E")[0].
		SET d_engine:THRUSTLIMIT TO 100.

		PRINT "Bob: calculating braking burn".
		WAIT 1.

		descent["Calc_Brakepoint"]().
		WAIT 0.
		
		goNext(). 
	}).

	// do the braking burn
	seq:ADD( {
		
		descent["Braking_Burn"]().
		WAIT 0.
		
		goNext(). 
	}).

	// do landing burn,
	// but abort if we will die
	seq:ADD( {
		
		// TODO:confirm we are in a flat-ish spot and have enough dV to land
		
		// if not: abort
		
		// if so: land
		descent["Landing_Burn"]().
	
		goNext().
	}).

	// pop the corks
	seq:ADD({ 
		IF SHIP:STATUS = "Landed" {
			UNLOCK STEERING.
			LOCK THROTTLE TO 0.
			RCS OFF.
			SAS ON.
			FUELCELLS OFF.
			LOCAL d_engine IS SHIP:PARTSTAGGED("DESCENT_E")[0].
			SET d_engine:THRUSTLIMIT TO 0.0.
			
			PRINT "Bill: copy you down, Urkel".
			goNext(). 
		}
	}).

	// get out and walk around
	seq:ADD( { IF SHIP:CREW():LENGTH = 0 goNext(). }).
	
	// wait until everybody is back in
	seq:ADD( { IF SHIP:CREW():LENGTH = 2 goNext(). }).

	// calculate time to launch for direct-ish ascent
	seq:ADD( {
	
		SET theCM TO VESSEL("Acapella").
		
		LOCAL ascentTime IS 0.    	// there may be a way to calculate this since we are in vacuum
		LOCAL downrangeDegs IS 0.	// need to get empirical data for this
		LOCAL launchDetails IS launch:Find_Window(theCM, 0, 0, 0, ascentTime, downrangeDegs, 0).

		SET launchAzimuth TO launchDetails:AZIMUTH.
		SET launchETA TO launchDetails:L_ETA.
		
		UNTIL TIME:SECONDS > TIME:SECONDS -launchETA { WAIT 0. }	
		goNext().
	
	}).

	// get off the mun
	seq:ADD( {
	
		LOCAL westVector IS ANGLEAXIS(-90, SHIP:UP:FOREVECTOR) * SHIP:NORTH:FOREVECTOR.
		LOCAL controlSteering IS LOOKDIRUP(HEADING(270,90):FOREVECTOR, westVector).
		LOCK STEERING TO SHIP:FACING.
		LOCK THROTTLE TO 0.
				
		SET theLM TO SHIP:PARTSTAGGED("theLM")[0].
		FOR rs IN theLM:RESOURCES {
			IF rs:NAME = "ELECTRICCHARGE" rs:ENABLED ON.
			IF rs:NAME = "MONOPROPELLANT" rs:ENABLED ON.
			IF rs:NAME = "LIQUIDFUEL" rs:ENABLED ON.
			IF rs:NAME = "OXIDIZER" rs:ENABLED ON.
		}
		
		PRINT "Bob: Preparing to launch".
		LOCK THROTTLE TO 1.		
		WAIT 8.
		FUELCELLS ON.
		
		// decouple
		LOCAL e_asc IS SHIP:PARTSTAGGED("ASCENT_E")[0].
		LOCAL d_dec IS SHIP:PARTSTAGGED("DESC_DECOUPLER")[0].
		
		d_dec:GETMODULE("ModuleDecouple"):DOEVENT("Decouple").
		e_asc:ACTIVATE.

		WAIT 1.
		LOCK STEERING TO controlSteering.
		WAIT 4.

		SET controlSteering TO LOOKDIRUP(HEADING(270,25):FOREVECTOR, -SHIP:UP:VECTOR).
		UNTIL ALT:RADAR > 3000 WAIT 0.
		
		PRINT "Bob: lock to prograde vector".
		LOCK controlPitch TO  (90 - VANG(SHIP:UP:VECTOR, SHIP:PROGRADE:FOREVECTOR)).
		SET controlSteering TO LOOKDIRUP(HEADING(270,controlPitch):FOREVECTOR, -SHIP:UP:VECTOR).
		WAIT 2.
		PRINT "Jeb: locked to prograde".
		
		PRINT "Bob: burning to apoapsis".
		UNTIL SHIP:OBT:APOAPSIS >= TARGET_MUNAR_ALTITUDE - 6000. {
			WAIT 0.
		}

		UNTIL SHIP:OBT:APOAPSIS >= TARGET_MUNAR_ALTITUDE - 5000 {
			LOCK THROTTLE TO MAX(1 - SHIP:OBT:APOAPSIS / TARGET_MUNAR_ALTITUDE, 0.1).
			WAIT 0.
		}

		LOCK THROTTLE TO 0.
		FUELCELLS OFF.
		PRINT "Jeb: Target apoapsis achieved".
		
		goNext().
	}).

	// get into a a low parking orbit
	seq:ADD( {

		WAIT 5.
		PRINT "Bob: calculating parking orbit".
		
		// calculate burn to circularize at desired altitude
		tranzfer:Node_For_PE(SHIP:OBT:APOAPSIS).

		PRINT "Bob: orbital burn in " + Round(NEXTNODE:ETA) + "s".
		
		// do the burn
		tranzfer["Exec"]().
		
		LOCK THROTTLE TO 0.0.
		LOCK STEERING TO LOOKDIRUP(SHIP:RETROGRADE:VECTOR, SHIP:UP:VECTOR).
				
		PRINT "Jeb: orbital insertion complete".
		goNext().
	  }).

	// TODO: add sequence step to rendezvous with CM.
	// TODO: add sequence step to dock with CM.

	// wait until we separate from the CM
	seq:ADD( { 
		IF SHIP:CREW():LENGTH = 0 goNext(). 
	}).

	// deorbit?
	seq:ADD( { 
		// turn retrograde
		// move away as before
		// burn until PE is inside the mun
		
		goNext(). 
	}).
	
	// make an event to go offline?  does it matter?
	
}).

Export(m_lm).