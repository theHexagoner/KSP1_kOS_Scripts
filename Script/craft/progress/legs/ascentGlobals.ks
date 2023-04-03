@LAZYGLOBAL OFF.

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 	TUNABLE PARAMETERS                                                                                                  ////
//	These params are tuned to work for launching a Soyuz/Progress spacecraft to LKO/KSS									////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// this should be 1/2 the duration (in seconds) of the ascent burn (all stages)
// used to predict launch window for intercepting the KSS orbit
declare global halfLaunchSecs is 160.0.

// The pitch program end altitude is the altitude, in meters, at which we level out to a pitch of 0° off the horizontal.
// this seems to be more or less constrained to the top of the altitude when using the sqrt solution for controlling pitch
declare global pitchProgramEndAltitude is 91500.0.  // meters

// This parameter controls the shape of the ascent curve.
declare global pitchProgramExponent is  0.45.

// This is the airspeed in m/s to begin the pitch program 
declare global pitchProgramAirspeed is 80.0.

// Dynamic pressure, in atmospheres, at which to jettison the payload fairings.
declare global fairingJettisonQ is  0.001.  



