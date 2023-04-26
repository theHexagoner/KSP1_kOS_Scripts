@LAZYGLOBAL OFF.
ABORT OFF.
SAS OFF.
RCS OFF.

// Example Mission Script for the Making History "Acapello" C/SM.
// derived from KSProgramming video series by Cheers Kevin Games

SET CONFIG:IPU TO 2000.0.

LOCAL mission IS Import("mission").
LOCAL tranzfer IS Import("transfer").
LOCAL rsvp IS Import("rsvp/main").
LOCAL docking IS Import("dock").
LOCAL abortMode IS Import("abort_cm").

LOCAL LAUNCH_AP IS 185000.
LOCAL PP_END IS 92000.
LOCAL RETURN_PE IS 24000. 

LOCAL FUNCTION gee { RETURN SHIP:BODY:MU / ((SHIP:ALTITUDE + SHIP:BODY:RADIUS)^2). }
LOCAL FUNCTION availTWR { RETURN SHIP:AVAILABLETHRUST / (SHIP:MASS * gee()). }

LOCAL freeze IS tranzfer["Freeze"].
LOCAL timeout IS 0.

LOCAL m_cm IS mission( { 
	PARAMETER seq, 		// mission sequence
			  evts,  	// mission events
			  goNext. 	// what happens next

	evts:ADD( "SET_ABORT_MODE", abortMode:SET_ABORT_MODE@ ).
	evts:ADD( "ON_ABORT",  abortMode:RUN_ABORT_MODE@).

	// enjoy the bumpy ride to orbit
	seq:ADD( {
		// await notification that LV has completed transfer burn
		IF NOT CORE:MESSAGES:EMPTY {
			LOCAL packet IS CORE:MESSAGES:POP().
			LOCAL data IS packet:CONTENT.
			IF data[0] = TRUE {
				IF data[1] = "LV: HANDOFF" goNext().
			}
		}
		
		WAIT 0.
	}).

	// we choose to go to the Mun!
	// assume we are in free-return trajectory
	
	// separate from the Saturn/LM
	seq:ADD( {
	
		PRINT "Bill: Handoff from IPU accepted".
		
		// remove any nodes in case there are some, somehow
		UNTIL NOT HASNODE { REMOVE NEXTNODE. WAIT 0. }
		
		LOCK THROTTLE TO 0.
		LOCK STEERING TO SHIP:PROGRADE.

		// wait until we are well on our way
		WAIT UNTIL SHIP:ALTITUDE >= 2000000.
		
		PRINT "Bill: preparing to decouple from booster".

		// decouple from the Saturn/LM
		LOCAL LV_DECOUPLER IS SHIP:PARTSTAGGED("LV_DECOUPLER")[0].
		LV_DECOUPLER:GETMODULE("ModuleDecouple"):DOEVENT("Decouple").
		WAIT 1.0.
	
		PRINT "Jeb: decoupled from booster".
		
		goNext().
	}).
	
	// move away from the LV
	seq:ADD( {
		
		IF VESSEL("Saturn"):DISTANCE < 25.0 {

			// puff out some RCS and move away at 1 m/s
			LOCK THROTTLE TO 0.
			LOCK STEERING TO SHIP:PROGRADE.

			LOCAL lmp IS VESSEL("Saturn"):PARTSTAGGED("theLM_PORT")[0].
			LOCAL cmp IS SHIP:PARTSTAGGED("theCM_PORT")[0].
			LOCAL offsets IS LEXICON("FORE", 30, "TOP", 0, "STAR", 0).

			IF docking:CONFIGURE(cmp, lmp, offsets, false) {
				WAIT 0.
				docking:EXEC().
			} ELSE {
				PRINT "Jeb: better do this myself!".
			}
			
			// make sure we have cleared the LV
			UNTIL VESSEL("Saturn"):DISTANCE > 25.0 WAIT 0.
			PRINT "BILL: We're away, prepare to jettison fairing".
			WAIT 1.
		}

		goNext().
	}).

	// release the fairing
	seq:ADD( {

		LOCAL relay IS SHIP:PARTSTAGGED("RELAY")[0].
		relay:GETMODULE("ModuleDeployableAntenna"):DOEVENT("Extend Antenna").
		WAIT 3.
		
		// instruct the LV to jettison the LM fairings
		PRINT "Jeb: releasing the fairing".
		SET timeout TO TIME:SECONDS + 600.
		WAIT UNTIL VESSEL("Saturn"):CONNECTION:ISCONNECTED OR TIME:SECONDS >= timeout.
		
		LOCAL done IS FALSE.
		
		UNTIL done {
			IF VESSEL("Saturn"):CONNECTION:SENDMESSAGE(LIST(TRUE, "CM: RELEASE FAIRING")) {
				// wait for confirmation that fairing has been released
				IF NOT SHIP:MESSAGES:EMPTY {
					LOCAL packet IS SHIP:MESSAGES:POP().
					LOCAL data IS packet:CONTENT.
					IF data[0] = TRUE {
						IF data[1] = "LV: JETTISON CONFIRMED" {
							PRINT "Bill: jettison confirmed".
							SET done TO TRUE.
						} ELSE PRINT data[1].
					}
					WAIT 0.
				}						
			} 		
		}
		
		goNext().
	}).

	// dock with the LM
	seq:ADD( {

		PRINT "Bill: prepare for docking".
		
		// rotate to face the LM docking port
		SET TARGET TO VESSEL("Saturn"):PARTSTAGGED("theLM_PORT")[0].
	
		docking:CONFIGURE(SHIP:PARTSTAGGED("theCM_PORT")[0]).
		WAIT 0.
		docking:EXEC().

		WAIT UNTIL SHIP:PARTSTAGGED("theCM_PORT")[0]:STATE:CONTAINS("Docked").
		
		PRINT "Bill: docking confirmed".
		
		LOCK THROTTLE TO 0.
		LOCK STEERING TO "KILL".

		WAIT UNTIL SHIP:ANGULARVEL:MAG < 0.010.

		goNext().
	}).

	// notify the LV that it can separate
	seq:ADD( {
		WAIT 10.
		PRINT "Jeb: separating from Saturn".
		WAIT 2.
		
		LOCAL linkToLV_CPU TO SHIP:PARTSTAGGED("theLV")[0]:GETMODULE("kOSProcessor"):CONNECTION.
		linkToLV_CPU:SENDMESSAGE(LIST(TRUE, "CM: SEPARATE")).

		goNext().
	}).

	// await notification that LV has separated 
	seq:ADD( {
		
		LOCAL done IS FALSE.
		UNTIL done {
		
			// await notification that LV has separated 
			IF NOT SHIP:MESSAGES:EMPTY {
				LOCAL packet IS SHIP:MESSAGES:POP().
				LOCAL data IS packet:CONTENT.
				IF data[0] = TRUE {
					IF data[1] = "LV: COUPLING DISENGAGED" {
						SET done TO TRUE.
						PRINT "Jeb: confirming separation".
						WAIT 2.
					}
				}
				WAIT 0.
			}
		}
				
		goNext().
	}).

	// move away from the LV with the LM
	seq:ADD( {
		
		LOCK THROTTLE TO 0.
		LOCK STEERING TO "KILL".		
		
		LOCAL lv IS VESSEL("Saturn").
		LOCAL cm IS SHIP:PARTSTAGGED("theCM")[0].		
		
		IF VESSEL("Saturn"):DISTANCE < 10.0 {
			LOCAL offsets IS LEXICON("FORE", 15, "TOP", 0, "STAR", 0).

			IF docking:CONFIGURE(cm, lv, offsets, false) {
				WAIT 0.
				docking:EXEC().
			} ELSE {
				PRINT "Jeb: better do this myself!".
			}
			
			// make sure we have cleared the LV
			UNTIL VESSEL("Saturn"):DISTANCE > 10.0 WAIT 0.
			PRINT "BILL: We're away".
			WAIT 1.
		}
		
		IF VESSEL("Saturn"):DISTANCE >= 10.0 AND VESSEL("Saturn"):DISTANCE < 45.0 {
			LOCAL offsets IS LEXICON("FORE", 15, "TOP", -50, "STAR", 0).
			
			IF docking:CONFIGURE(cm, lv, offsets, false) {
				WAIT 0.
				docking:EXEC().
			} ELSE {
				PRINT "Jeb: better do this myself!".
			}		
			
			PRINT "Jeb: Waiting to clear the booster".

		}

		WAIT UNTIL VESSEL("Saturn"):DISTANCE > 45.0.
		PRINT "Jeb: Cleared the booster".
		LOCK STEERING TO SHIP:RETROGRADE.

		goNext().
	}).

	// await notification that LV has completed transfer
	seq:ADD( {
		
		LOCAL done IS FALSE.
		
		UNTIL done {
			
			IF NOT SHIP:MESSAGES:EMPTY {
				LOCAL packet IS SHIP:MESSAGES:POP().
				LOCAL data IS packet:CONTENT.
				IF data[0] = TRUE {
					IF data[1] = "LV: MISSION TERMINATED" {
						SET done TO TRUE.
						goNext().
					}
				}
				WAIT 0.
			}
		}
		
		goNext().
	}).
	
	// make a correction burn?
	seq:ADD( {
	
		UNTIL FALSE {
			WAIT 0.
		
		}

		goNext().
	}).

	// is there a way to do a bbq roll (style points)
	seq:ADD( {
		// TODO: barbecue roll?
		goNext().
	}).

	// if we get bored
	seq:ADD({
		// warp to the SOI change?
		goNext().
	}).

	// enter the Mun SOI
	seq:ADD( {
		IF SHIP:BODY = Mun {
			WAIT 30.
			goNext().
		}
	}).

	// make a circularization node
	seq:ADD( {
		UNTIL NOT HASNODE { REMOVE NEXTNODE. WAIT 0. }
		PRINT "Bill: looking for parking orbit".
		tranzfer:Node_For_AP(SHIP:OBT:PERIAPSIS).
		goNext().
	}).

	// do the node
	seq:ADD( {
		
		// make sure the node is there
		IF NOT HASNODE { 
			PRINT "Bill: looking for parking orbit".
			tranzfer:Node_For_AP(SHIP:OBT:PERIAPSIS). 
			WAIT 0. 
		}

		PRINT "Jeb: waiting to park it".
		WAIT 1.0.
				
		tranzfer["Exec"]().
		LOCK THROTTLE TO 0.
		LOCK STEERING TO SHIP:PROGRADE.
		WAIT 1.0.

		PRINT "Jeb: we are in orbit around the Mun".
		goNext().
	}).

	// plan for when to hand-off to landing mission?

	// wait for folks to move to the LM and for it to separate
	seq:ADD( { IF SHIP:CREW():LENGTH = 1 goNext(). }).

	// do stuff after the LM is gone?
	seq:ADD( {
		WAIT 60.
		PRINT "Bill: I wish I had brought more snacks...".
		goNext().
	}).

	seq:ADD( { 
		IF SHIP:CREW():LENGTH = 3 {
			PRINT "Bill: welcome back!".
			goNext(). 
		}
	}).

	// TODO: add step to drop the LM

	// get a return trajectory
	seq:ADD({
		tranzfer["Seek_SOI"](Kerbin, TARGET_RETURN_ALTITUDE).
		tranzfer["Exec"]().
		goNext().
	}).

	// get out of Mun SOI
	seq:ADD( {
		LOCAL transition_time IS TIME:SECONDS + ETA:TRANSITION.
		WARPTO(transition_time).
		WAIT UNTIL TIME:SECONDS >= transition_time.
		goNext().
	}).

	// when we are in Kerbin SOI, correct our burn to get an accurate re-entry altitude
	seq:ADD( {
		IF BODY = Kerbin {
			WAIT 30.
			tranzfer["Seek"](
				freeze(TIME:SECONDS + 120), 
				freeze(0), 
				freeze(0), 
				0,
				{ PARAMETER mnv. RETURN -abs(mnv:orbit:periapsis - TARGET_RETURN_ALTITUDE). }
			).
			tranzfer["Exec"]().
		goNext().
		}
	}).

	// when we are nearing Kerbin
	// TODO: attempt to predict landing in the big oceans near KSC

	// ditch the SM
	seq:ADD({
		IF SHIP:ALTITUDE < LAUNCH_AP * 2 {
			// TODO: drop the SM
			goNext().
		} ELSE {
			// wait around, play cards, eat snacks
		}
	}).

	// ride the fireball
	// TODO: add some logic to try and control descent to avoid landing on land
	seq:ADD( {
		IF SHIP:ALTITUDE < PP_END {
			LOCK STEERING TO SHIP:SRFRETROGRADE.
		    goNext().
		}
	}).

	seq:ADD({ IF SHIP:STATUS = "Landed" goNext(). }).
	
}).

Export(m_cm).