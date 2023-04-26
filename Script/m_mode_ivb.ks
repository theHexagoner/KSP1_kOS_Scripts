@LAZYGLOBAL OFF.

{
ABORT OFF.
SAS OFF.
RCS OFF.

// Example Mission Script for the Making History "Acapello" launch vehicle. 
// This script represents the Saturn Abort Mode IV-B, which uses the S-IVB stage 
// propulsion to replace a failed S-II stage.

// Derived from the "mission runner" concept presented by KSProgramming video series by Cheers Kevin Games

// reduce this when we figure out how much it needs to be
SET CONFIG:IPU TO 2000.0.

// This is kind of a hack to damp roll oscillations
// also, keep the craft from rolling around slowly after lauch:
SET STEERINGMANAGER:ROLLTS TO 5.0.
SET STEERINGMANAGER:ROLLCONTROLANGLERANGE TO 180.

// IMPORTS
LOCAL mission IS Import("mission").
LOCAL tranzfer IS Import("transfer").
LOCAL abortMode IS Import("abort_ivb").

// MISSION PARAMS
LOCAL LAUNCH_AP IS 120000.
LOCAL PP_START IS 0.0.
LOCAL PP_END IS 92000.
LOCAL PP_EXP IS 0.75.

LOCAL CONTROL_PITCH IS 0.0.
LOCAL NOMINAL_THRUST IS 0.

// TIMESTAMPS
LOCAl t_launch IS 0.
LOCAL countdown IS 10.
LOCAL ts_Mark IS 0.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 	During each loop, the mission will execute every one of its events, but it will only execute the current sequence.
// 	For craft with multiple processors, it is importatn to avoid when and until or other loops inside these functions so
//	that they will be able to respond to user inputs (action groups, etc.) in a timely manner
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL this IS mission( { 
	PARAMETER seq, 		// mission sequence
			  evts,  	// mission events
			  goNext. 	// what happens next
	
	evts:ADD( "SET_ABORT_MODE", abortMode:SET_ABORT_MODE@).	
	evts:ADD( "ON_ABORT", abortMode:RUN_ABORT_MODE@).

	// in abort mode IVB, adjust mission params.
	seq:ADD( {
		IF (SHIP:STATUS = "FLYING" OR SHIP:STATUS = "SUB_ORBITAL") {
			// update guidance
			LOCK pctAlt to (SHIP:ALTITUDE-PP_START)/PP_END.
			LOCK controlPitch TO MAX(0.0, 90 -90*pctAlt^PP_EXP).
			LOCK STEERING TO HEADING(90, controlPitch + 5).	
			LOCK THROTTLE TO 1.0.
			PRINT "LV: guidance updated for Abort Mode IVB".
			ABORT OFF.
			goNext().
		} ELSE goNext().
	}).
	
	// when we hit our APO target, kill the throttle
	seq:ADD( {
		IF (SHIP:STATUS = "FLYING" OR SHIP:STATUS = "SUB_ORBITAL" OR SHIP:STATUS = "ORBITING") {
			IF SHIP:OBT:APOAPSIS > LAUNCH_AP {
				LOCK THROTTLE TO 0.
				LOCK STEERING TO SHIP:PROGRADE.
				PRINT "LV: target APO reached".
				goNext().
			}
		} ELSE goNext().
	}).

	// get node for emergency orbit after we get to space
	seq:ADD( {
		IF (SHIP:STATUS = "SUB_ORBITAL" OR SHIP:STATUS = "ORBITING") {
			IF SHIP:OBT:ECCENTRICITY >= 0.0005 AND SHIP:OBT:PERIAPSIS < PP_END + 1000 {
				IF ts_Mark = 0 {
					UNTIL NOT HASNODE { REMOVE NEXTNODE. WAIT 0. }
					PRINT "LV: calculating emergency orbit".
					tranzfer:Node_For_PE(PP_END + 1000).

					// do we have enough dV to do this burn?
					LOCAL stageNum IS 5. // guess?
					IF NOT SHIP:PARTSTAGGED("S3_Engine"):EMPTY AND
				       SHIP:PARTSTAGGED("S3_Engine")[0]:IGNITION SET stageNum TO SHIP:PARTSTAGGED("S3_Engine")[0]:STAGE.

					IF SHIP:STAGEDELTAV(stageNum):CURRENT < NEXTNODE:BURNVECTOR:MAG {
						// we have failed
						ABORT ON.
						goNext().
					}

					LOCAL burnETA IS ETA:NEXTNODE - tranzfer:GET_BURNTIME(NEXTNODE:BURNVECTOR:MAG):MEAN.
					PRINT "LV: perform orbital burn in " + burnETA + "s".
					SET ts_Mark TO TIME:SECONDS + burnETA.
				}

				IF TIME:SECONDS >= ts_Mark {
					tranzfer["Exec"]().
					LOCK THROTTLE TO 0.
					LOCK STEERING TO LOOKDIRUP(SHIP:PROGRADE:VECTOR, SHIP:UP:VECTOR).
					goNext().
				}
				
			} ELSE { goNext(). }
		} ELSE goNext().
	}).

	// attempt to further correct into parking orbit around Kerbin
	seq:ADD( {
		IF (SHIP:STATUS = "ORBITING") {
			IF SHIP:OBT:ECCENTRICITY >= 0.0005  {
				IF ts_Mark < TIME:SECONDS {
					UNTIL NOT HASNODE { REMOVE NEXTNODE. WAIT 0. }
					PRINT "LV: calculating parking orbit".
					tranzfer:Node_For_PE(SHIP:OBT:APOAPSIS).

					LOCAL burnETA IS ETA:NEXTNODE - tranzfer:GET_BURNTIME(NEXTNODE:BURNVECTOR:MAG):MEAN .
					PRINT "LV: perform orbital burn in " + burnETA + "s".
					SET ts_Mark TO TIME:SECONDS + burnETA.
				}
				
				IF TIME:SECONDS >= ts_Mark {
					tranzfer["Exec"]().
					LOCK THROTTLE TO 0.
					LOCK STEERING TO LOOKDIRUP(SHIP:PROGRADE:VECTOR, SHIP:UP:VECTOR).
					goNext().
				}

			} ELSE { goNext(). }
		} ELSE goNext().
	}).

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//  ASCENT COMPLETE, HANDOFF TO ACAPELLA
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	// notify the payload CPU
	seq:ADD( {
		IF MISSION_ABORT AND SHIP:STATUS = "ORBITING" {
			PRINT "LV: handing off to CM".
			LOCAL linkToCM_CPU TO SHIP:PARTSTAGGED("theCM")[0]:GETMODULE("kOSProcessor"):CONNECTION.
			linkToCM_CPU:SENDMESSAGE(LIST(TRUE, "LV: HANDOFF")).
			WAIT 0.
		}
		goNext().
	}).

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//  UNPACK THE LANDER
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	// wait for the CM to separate
	seq:ADD( {
		IF SHIP:STATUS = "ORBITING" {
			PRINT "LV: waiting at 272".
			WAIT UNTIL SHIP:CREW():LENGTH = 0.
			LOCK STEERING TO SHIP:PROGRADE.
			LOCK THROTTLE TO 0.
			goNext().
		} ELSE goNext().
	}).
	
	// wait for instructions from CM
	seq:ADD( {
		IF SHIP:STATUS = "ORBITING" {
		
			LOCAL done IS FALSE.
			
			PRINT "LV: waiting for instruction 286".
			
			UNTIL done {
				IF NOT SHIP:MESSAGES:EMPTY {
									
					LOCAL packet IS SHIP:MESSAGES:POP().
					LOCAL data IS packet:CONTENT.
					IF data[0] = TRUE {
						IF data[1] = "CM: RELEASE FAIRING" {
							PRINT "CM: RELEASE FAIRING".
	
							IF NOT SHIP:PARTSTAGGED("LM_FAIRING"):EMPTY {
								LOCAL dec IS SHIP:PARTSTAGGED("LM_FAIRING")[0].
								dec:GETMODULE("ModuleProceduralFairing"):DOEVENT("Deploy").
								WAIT 3.						
							}
							
							LOCK STEERING TO SHIP:PROGRADE.
							LOCK THROTTLE TO 0.
	
							PRINT "LV: fairing jettisoned".
							VESSEL("Acapella"):CONNECTION:SENDMESSAGE(LIST(TRUE, "LV: JETTISON CONFIRMED")).
							
							SET done TO TRUE. // redundant?
							goNext().
						}
					}
				}
				WAIT 0.
			}
		} ELSE goNext().
	}).	
	
	// wait for the CM to almost dock?
	seq:ADD( {
		IF SHIP:STATUS = "ORBITING" {
			LOCK dPos TO SHIP:PARTSTAGGED("theLM_PORT")[0]:NODEPOSITION.
			LOCK tPos TO VESSEL("Acapella"):PARTSTAGGED("theCM_PORT")[0]:NODEPOSITION.
			LOCK cdist TO (dPos - tPos):MAG.
		
			WAIT UNTIL cdist < 1.0.
			
			// relax and enjoy it
			RCS OFF.
			SAS OFF.
			SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
			UNLOCK STEERING.
			UNLOCK THROTTLE.
			WAIT 0.
		
			goNext().
		
		} ELSE goNext().
	}).
	
	// wait until we are docked
	seq:ADD( {
		IF SHIP:STATUS = "ORBITING" {
			PRINT "LV: waiting at 342".
			WAIT UNTIL SHIP:CREW():LENGTH > 0.
			PRINT "LV: confirm docking".
			goNext().
		} ELSE goNext().		
	}).
		
	// wait for instruction from CM
	seq:ADD( {
		IF SHIP:STATUS = "ORBITING" {
		
			LOCAL done IS FALSE.
			PRINT "LV: waiting for instruction 422".
			
			UNTIL done {
				IF NOT CORE:MESSAGES:EMPTY {
					LOCAL packet IS CORE:MESSAGES:POP().
					LOCAL data IS packet:CONTENT.
					IF data[0] = TRUE {
						IF data[1] = "CM: SEPARATE" {
							PRINT "CM: SEPARATE".
	
							LOCAL dec IS SHIP:PARTSTAGGED("S3_DECOUPLER")[0].
							dec:GETMODULE("ModuleDecouple"):DOEVENT("Decouple").
							WAIT 3.						
	
							PRINT "LV: coupling disengaged".
							VESSEL("Acapella"):CONNECTION:SENDMESSAGE(LIST(TRUE, "LV: COUPLING DISENGAGED")).

							SET done TO TRUE. // redundant?
							goNext().
						}
					}
				}
				WAIT 0.			
			}

		} ELSE goNext().
	}).
	
	// verify we are separated from the Acapella spacecraft
	seq:ADD( { 
		IF SHIP:STATUS = "ORBITING" {
			IF SHIP:CREW():LENGTH = 0 {
				PRINT "LV: confirm separation".
				goNext(). 
			}
			WAIT 0. 
		} ELSE goNext().
	}).	
	
	// wait until Acapella has moved away to a safe distance
	seq:ADD( { 
		IF SHIP:STATUS = "ORBITING" {
			IF (POSITIONAT(SHIP, TIME:SECONDS) - POSITIONAT(VESSEL("Acapella"), TIME:SECONDS)):MAG > 45.0 {
				PRINT "LV: spacecraft is at minsafe".
				LOCK STEERING TO SHIP:PROGRADE.
				goNext().
			}
			WAIT 0. 
		} ELSE goNext().
	}).
		
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//  OUR WORK IS DONE, PREPARE TO DIE
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	// do a deorbit burn
	seq:ADD( {
		IF SHIP:STATUS = "ORBITING" {

			VESSEL("Acapella"):CONNECTION:SENDMESSAGE(LIST(TRUE, "LV: MISSION TERMINATED")).

			RCS ON.
			SET SHIP:CONTROL:FORE TO -1.
			WAIT UNTIL SHIP:OBT:PERIAPSIS < 10000.
			SET SHIP:CONTROL:FORE TO 0.
			WAIT 0.			
			CORE:DEACTIVATE().
		}
	}).
	
}).

// EXPORT THE MISSION
Export(this).
}