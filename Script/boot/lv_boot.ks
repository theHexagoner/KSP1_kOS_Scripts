@LAZYGLOBAL OFF.
WAIT UNTIL SHIP:UNPACKED.

// this is a boot file for an example launch vehicle (e.g. Acapello)

// FOR TESTING
SWITCH TO 1.
PRINT "Deleting test files...".

FOR f IN LIST (
	"knu.ks",
	"mission.ks",
	"m_lv.ks",
	"m_mode_ivb",
	"abort.ks",
	"abort_lv.ks",
	"abort_ivb.ks",
	"transfer.ks",
	"descent.ks",
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
// if we don't find one, the load the default mission to
// launch for munar injection of Acapello spacecraft
LOCAL mm IS "m_lv.ks".

GLOBAL MISSION_MODE IS "1:/mission_mode.ks".
IF EXISTS(MISSION_MODE) SET mm TO Import("mission_mode.ks").

PRINT mm.

IMPORT(mm)().

