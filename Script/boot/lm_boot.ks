@LAZYGLOBAL OFF.
WAIT UNTIL SHIP:UNPACKED.

// this is a boot file for an example mun lander (e.g. Acapello)

// FOR TESTING
SWITCH TO 1.
FOR f IN LIST (
	"knu.ks",
	"mission.ks",
	"m_lm.ks",
	"transfer.ks",
	"descent.ks",
	"abort.ks",
	"abort_lm.ks",
	"rsvp/hill_climb.ks",
	"rsvp/lambert.ks", 
	"rsvp/main.ks",
	"rsvp/maneuver.ks",
	"rsvp/orbit.ks",
	"rsvp/refine.ks",
	"rsvp/search.ks",
	"rsvp/transfer.ks",
	"rsvp/validate.ks"
) DELETEPATH("1:/" + f).

IF NOT EXISTS("1:/knu.ks") COPYPATH("0:/knu.ks", "1:/").
RUNPATH("1:/knu.ks"). 


// look for a mission_mode.ks to tell us what mission to load
LOCAL mmf IS "1:/mission_mode.ks".

// if we don't find one, the load the default mission

// pre-launch (as cargo)
IMPORT("m_lm.ks")().

// else:

// lifeboat (e.g. Apollo 13)??
// return to Gateway?
// extended stay?
// ??

