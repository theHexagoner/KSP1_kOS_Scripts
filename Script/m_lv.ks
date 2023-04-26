@LAZYGLOBAL OFF.

{
ABORT OFF.
SAS OFF.
RCS OFF.

// Example Mission Script for the Making History "Acapello" launch vehicle.
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
LOCAL descent IS Import("descent").
LOCAL rsvp IS Import("rsvp/main").
LOCAL abortMode IS Import("abort_lv").

// MISSION PARAMS
LOCAL LAUNCH_AP IS 195000.
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

LOCAL m_lv IS mission( { 
	PARAMETER seq, 		// mission sequence
			  evts,  	// mission events
			  goNext. 	// what happens next
	
	evts:ADD( "SET_ABORT_MODE", abortMode:SET_ABORT_MODE@).	
	evts:ADD( "ON_ABORT", abortMode:RUN_ABORT_MODE@).

	// initialize flight
	seq:ADD( {
		IF SHIP:STATUS = "PRELAUNCH" {
			PRINT "LV: Pre-launch".
	
			// cancel any open throttle
			SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
			LOCK THROTTLE TO 0.
			LOCK STEERING TO HEADING(90, 90).
			WAIT 0.
			
			SET ts_Mark TO TIME:SECONDS.
			SET t_launch TO ts_Mark + 10.
			HUDTEXT("T-minus 10", 1, 2, 30, YELLOW, false).
			goNext().

		} ELSE goNext().
	}).
	
	// countdown
	seq:ADD( {
		IF SHIP:STATUS = "PRELAUNCH" {
			IF TIME:SECONDS >= t_launch {
				goNext().
			} ELSE IF TIME:SECONDS >= ts_Mark + 1 {
				SET countdown TO countdown -1.
				SET ts_Mark TO TIME:SECONDS.
				
				IF countdown >= 6 OR countdown <= 4 {
					LOCAL str IS "   . . . " + countdown.
					HUDTEXT(str, 1, 2, 30, YELLOW, false).
				} ELSE {
					HUDTEXT("IGNITION", 1, 2, 30, YELLOW, false).
				}
			} 
			// at go-time turn on the engines
			IF NOMINAL_THRUST = 0 AND TIME:SECONDS >= t_launch -5.4 {
				IF NOT SHIP:PARTSTAGGED("F1_Center"):EMPTY {
					SHIP:PARTSTAGGED("F1_Center")[0]:ACTIVATE().
					FOR en IN SHIP:PARTSTAGGED("F1_Outboard") {
						en:ACTIVATE().
					}
					WAIT 0.
	
					LOCK THROTTLE TO 1.
					WAIT 0.
	
					PRINT "LV: Ignition".
					SET NOMINAL_THRUST TO 0.001.
				}
			}
		} ELSE goNext().
	}).	

	// wait for engines to spool up
	seq:ADD( {
		IF SHIP:STATUS = "PRELAUNCH" {
			// when we reach nominal thrust:
			IF Get_Current_TWR() > 1.15 goNext().
		} ELSE goNext().
	}).
	
	// liftoff
	seq:ADD( {
		IF SHIP:STATUS = "PRELAUNCH" {
			IF NOT SHIP:PARTSTAGGED("CLAMP"):EMPTY {
				FOR cl IN SHIP:PARTSTAGGED("CLAMP") {
					cl:GETMODULE("LaunchClamp"):DOEVENT("Release Clamp").
				}
				WAIT 0.
				PRINT "LV: Liftoff".
				goNext().
			}
		} ELSE goNext().
	}).
	
	// initial ascent and begin pitch program
	seq:ADD( {
		IF SHIP:STATUS = "FLYING" {
			IF SHIP:VELOCITY:SURFACE:MAG > 50.0 {
		
				SET NOMINAL_THRUST TO SHIP:AVAILABLETHRUST.
				SET PP_START TO SHIP:ALTITUDE.
	
				LOCK pctAlt to (SHIP:ALTITUDE-PP_START)/PP_END.
				LOCK controlPitch TO MAX(0.0, 90 -90*pctAlt^PP_EXP).
				LOCK STEERING TO HEADING(90, controlPitch).
				SET ts_Mark TO TIME:SECONDS.
			
				PRINT "LV: Pitch program is running".
				goNext().
			}
		} ELSE goNext().
	}).
	
	// monitor ascent profile
	seq:ADD( {
		IF SHIP:STATUS = "FLYING" {
			// after letting things settle for 3 seconds:
			IF TIME:SECONDS >= ts_Mark + 3 {
				
				// if our surface prograde vector has caught up with out pointy end:
				IF Get_AoA() < 0.1 {
					LOCK controlPitch TO  (90 - VANG(SHIP:UP:VECTOR, SHIP:SRFPROGRADE:FOREVECTOR)).
					LOCK STEERING TO HEADING(90, controlPitch).
					FOR en IN SHIP:PARTSTAGGED("F1_Outboard") SET en:GIMBAL:LIMIT TO 15.0.
					PRINT "LV: holding prograde vector".
					goNext().
				}
			}
		} ELSE goNext().
	}).
	
	// center engine cutoff
	seq:ADD( {
		IF SHIP:STATUS = "FLYING" {
			
			// if we have pitched over significantly, cut thrust to help us maintain flight profile
			IF Get_Pitch() < 70.0 AND 
			   NOT SHIP:PARTSTAGGED("F1_Center"):EMPTY AND 
			   SHIP:PARTSTAGGED("F1_Center")[0]:IGNITION {
					SHIP:PARTSTAGGED("F1_Center")[0]:SHUTDOWN().
					WAIT 0.
					PRINT "LV: center engine cutoff".
					goNext().
			}
		} ELSE goNext().
	}).	
		
	// stage 1 flameout: make sure everything is shut down
	seq:ADD( {
		IF SHIP:STATUS = "FLYING" {
			IF SHIP:AVAILABLETHRUST < NOMINAL_THRUST * 0.75 {
				IF NOT SHIP:PARTSTAGGED("F1_Center"):EMPTY AND 
				   SHIP:PARTSTAGGED("F1_Center")[0]:IGNITION { SHIP:PARTSTAGGED("F1_Center")[0]:SHUTDOWN(). }
				
				FOR en IN SHIP:PARTSTAGGED("F1_Outboard") { IF en:IGNITION { en:SHUTDOWN(). }}
				PRINT "LV: S-IC flamout".
				goNext().
			}
		} ELSE goNext().
	}).

	// drop stage 1 when its TWR < 1.0
	seq:ADD( {
		IF SHIP:STATUS = "FLYING" {
			IF NOT SHIP:PARTSTAGGED("S1_DECOUPLER"):EMPTY {
				IF NOT SHIP:PARTSTAGGED("S1_SEP"):EMPTY {
					FOR en IN SHIP:PARTSTAGGED("S1_SEP") { IF NOT en:IGNITION { en:ACTIVATE(). }}
				}
				SHIP:PARTSTAGGED("S1_DECOUPLER")[0]:GETMODULE("ModuleDecouple"):DOEVENT("Decouple").
			}
			
			PRINT "LV: S-IC separation".
			SET ts_Mark TO TIME:SECONDS.
			goNext().
		} ELSE goNext().
	}).

	// fire stage 2 ullage
	seq:ADD( {
		IF SHIP:STATUS = "FLYING" {
			IF TIME:SECONDS >= ts_Mark + 0.3 {
				FOR en IN SHIP:PARTSTAGGED("S2_ULL") { en:ACTIVATE(). }
				SET ts_Mark TO TIME:SECONDS.
				goNext().
			}
		} ELSE goNext().	
	}).

	// fire stage 2 engines
	seq:ADD( {
		IF SHIP:STATUS = "FLYING" {
			IF TIME:SECONDS >= ts_Mark + 1.8 {
				FOR en IN SHIP:PARTSTAGGED("S2_Engine") { en:ACTIVATE(). }
				SET ts_Mark TO TIME:SECONDS + 2.
				goNext().	
			}
		} ELSE goNext().	
	}).	

	// resume following active guidance
	seq:ADD( {
		IF SHIP:STATUS = "FLYING" {
			IF TIME:SECONDS >= ts_Mark + 2 {
				LOCK pctAlt to (SHIP:ALTITUDE-PP_START)/PP_END.
				LOCK controlPitch TO MAX(0.0, 90 -90*pctAlt^PP_EXP).
				LOCK STEERING TO HEADING(90, controlPitch).			
				SET NOMINAL_THRUST TO SHIP:AVAILABLETHRUST.
				PRINT "LV: S-II is running".
				goNext().	
			}
		} ELSE goNext().	
	}).		

	// jettison the LES
	seq:ADD( {
		IF SHIP:STATUS = "FLYING" {
			IF SHIP:ALTITUDE > 60000 {
				SHIP:PARTSTAGGED("LES")[0]:ACTIVATE().			
				SHIP:PARTSTAGGED("theCM_PORT")[0]:GETMODULE("ModuleDockingNode"):DOEVENT("Undock").
				PRINT "LV: LES jettison".
				goNext().
			}
		} ELSE goNext().
	}).

	// when stage 2 flames out:
	seq:ADD( {
		IF (SHIP:STATUS = "FLYING" OR SHIP:STATUS = "SUB_ORBITAL") {
			IF SHIP:AVAILABLETHRUST < NOMINAL_THRUST * 0.75 {
				FOR en IN SHIP:PARTSTAGGED("S2_Engine") { IF en:IGNITION { en:SHUTDOWN(). }}
				PRINT "LV: S-II flameout".
				goNext().
			}
		} ELSE goNext().
	}).

	// drop stage 2
	seq:ADD( {
		IF (SHIP:STATUS = "FLYING" OR SHIP:STATUS = "SUB_ORBITAL") {
			IF TIME:SECONDS >= ts_Mark + 0.5 {
				FOR en IN SHIP:PARTSTAGGED("S2_SEP") { IF NOT en:IGNITION { en:ACTIVATE(). }}
				SHIP:PARTSTAGGED("S2_DECOUPLER")[0]:GETMODULE("ModuleDecouple"):DOEVENT("Decouple").
				PRINT "LV: S-II Separation".
				goNext().
			}

		} ELSE goNext().
	}).

	// fire the S3 ullage
	seq:ADD( {
		IF (SHIP:STATUS = "FLYING" OR SHIP:STATUS = "SUB_ORBITAL") {
			FOR en IN SHIP:PARTSTAGGED("S3_ULL") { en:ACTIVATE(). }
			SET ts_Mark TO TIME:SECONDS.
			goNext().
		} ELSE goNext().
	}).	

	// abort mode IVB, fire the S3 engine
	seq:ADD( {
		IF (SHIP:STATUS = "FLYING" OR SHIP:STATUS = "SUB_ORBITAL") {
			IF TIME:SECONDS >= ts_Mark + 3.5 {
				SHIP:PARTSTAGGED("S3_Engine")[0]:ACTIVATE().
				PRINT "LV: SIV-B is running".
				goNext().
			}
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

	// get node for parking orbit after we get to space
	seq:ADD( {
		IF (SHIP:STATUS = "FLYING" OR SHIP:STATUS = "SUB_ORBITAL" OR SHIP:STATUS = "ORBITING") {
			IF SHIP:ALTITUDE > PP_END AND SHIP:OBT:ECCENTRICITY >= 0.0005  {
				UNTIL NOT HASNODE { REMOVE NEXTNODE. WAIT 0. }
				PRINT "LV: calculating parking orbit".
				tranzfer:Node_For_PE(SHIP:OBT:APOAPSIS).
				LOCAL burnETA IS ETA:NEXTNODE -tranzfer:GET_BURNTIME(NEXTNODE:BURNVECTOR:MAG):MEAN.
				PRINT "LV: perform orbital burn in " + burnETA + "s".
				SET ts_Mark TO TIME:SECONDS + burnETA.
				goNext().
			}
		} ELSE goNext().
	}).

	// inject into parking orbit around Kerbin
	seq:ADD( {
		IF (SHIP:STATUS = "SUB_ORBITAL" OR SHIP:STATUS = "ORBITING") {
			IF SHIP:ALTITUDE > PP_END AND SHIP:OBT:ECCENTRICITY >= 0.0005  {

				// do we have enough dV to do the burn?
				LOCAL stageNum IS 5.  // happy path
				IF NOT SHIP:PARTSTAGGED("S3_Engine"):EMPTY AND
				   SHIP:PARTSTAGGED("S3_Engine")[0]:IGNITION SET stageNum TO SHIP:PARTSTAGGED("S3_Engine")[0]:STAGE.

				IF NOT SHIP:PARTSTAGGED("SM_E"):EMPTY AND
				   SHIP:PARTSTAGGED("SM_E")[0]:IGNITION SET stageNum TO SHIP:PARTSTAGGED("SM_E")[0]:STAGE.

				IF SHIP:STAGEDELTAV(stageNum):CURRENT < NEXTNODE:BURNVECTOR:MAG {
					// we have failed
					ABORT ON.
				}

				IF TIME:SECONDS >= ts_Mark {
					tranzfer["Exec"]().
					LOCK THROTTLE TO 0.
					LOCK STEERING TO SHIP:PROGRADE.
					goNext().
				}
			}
		} ELSE goNext().
	}).

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//  ASCENT COMPLETE, HANDOFF TO ACAPELLA
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	// We choose to go to the Mun!
	seq:ADD( {
		IF SHIP:STATUS = "ORBITING" {

			UNTIL NOT HASNODE { REMOVE NEXTNODE. WAIT 0. }
			PRINT "LV: seeking Mun transfer".
	
			LOCAL options is LEXICON("create_maneuver_nodes", "first", 
									"verbose", FALSE,
									"search_duration", SHIP:OBT:PERIOD + 120,
									"final_orbit_periapsis", 50000,
									"final_orbit_orientation", "retrograde",
									"max_time_of_flight", rsvp:ideal_hohmann_transfer_period(SHIP, Mun) * 2
									).
			
			LOCAL plan IS rsvp:Goto(Mun, options).
			
			IF NOT plan:SUCCESS {
				FOR p in plan:PROBLEMS {
					PRINT "" + p:KEY + ": " + p:VALUE.
				}
			} 
			
			PRINT "LV: Waiting to transfer".
				
			tranzfer["Exec"]().

			SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
			LOCK THROTTLE TO 0.
			LOCK STEERING TO SHIP:PROGRADE.

			// update the payload CPU	
			PRINT "LV: handing off to CM".
			LOCAL linkToCM_CPU TO SHIP:PARTSTAGGED("theCM")[0]:GETMODULE("kOSProcessor"):CONNECTION.
			linkToCM_CPU:SENDMESSAGE(LIST(TRUE, "LV: HANDOFF")).
				
			goNext().

		} ELSE goNext().
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
				goNext().
			}
			WAIT 0. 
		} ELSE goNext().
	}).
		
		
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//  OUR WORK IS DONE, PREPARE TO DIE
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	// in abort Mode IVB, we just do a deorbit burn
	seq:ADD( {
		IF MISSION_ABORT AND SHIP:STATUS = "ORBITING" {
			// make the deorbit burn
			goNext().
		} ELSE goNext().	
	}).
		
	// if we injected into Mun SOI, make a correction burn to fly into the Mun
	seq:ADD( {
		IF SHIP:STATUS = "ORBITING" {
			// make the correction burn
			// should be able to use RCS
			goNext().
		} ELSE goNext().	
	}).

	// notify the CM CPU we are terminating
	seq:ADD( {
		PRINT "LV: preparing to terminate".
		VESSEL("Acapella"):CONNECTION:SENDMESSAGE(LIST(TRUE, "LV: MISSION TERMINATED")).
		CORE:DEACTIVATE().
	}).
	
}).









////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//	UTILITY FUNCTIONS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

LOCAL FUNCTION Get_Local_Gee { RETURN SHIP:BODY:MU / ((SHIP:ALTITUDE + SHIP:BODY:RADIUS)^2). }
LOCAL FUNCTION Get_Available_TWR { RETURN SHIP:AVAILABLETHRUST / (SHIP:MASS * Get_Local_Gee()). }
LOCAL FUNCTION Get_Current_TWR  { RETURN SHIP:THRUST / (SHIP:MASS * Get_Local_Gee()). }
LOCAL FUNCTION Get_AoA { RETURN VANG(SHIP:VELOCITY:SURFACE, SHIP:FACING:FOREVECTOR). }
LOCAL FUNCTION Get_Pitch { RETURN 90 - VANG(UP:FOREVECTOR, SHIP:FACING:FOREVECTOR). }























// EXPORT THE MISSION
Export(m_lv).
}