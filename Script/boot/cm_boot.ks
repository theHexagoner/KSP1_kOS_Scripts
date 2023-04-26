@LAZYGLOBAL OFF.
WAIT UNTIL SHIP:UNPACKED.

// this is a boot file for an example C/SM for a Mun mission (e.g. Acapello)

// FOR TESTING
SWITCH TO 1.
FOR f IN LIST (
	"knu.ks",
	"mission.ks",
	"m_cm.ks",
	"abort.ks",
	"abort_cm.ks",
	"transfer.ks",
	"descent.ks",
	"dock.ks",
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

// we choose to go to the Mun!
IMPORT("m_cm.ks")().

// else:
// success mission splash party

// else else: 

// abort Mode IVB?
// rendezvous with KSS?
// rendezvous with Gateway?
// go to Minmus on a lark?

// else else else:

// emergency land or water rescue?
// orbital rescue from LKO?
// orbital rescue from HKO?
// orbital rescue from Mun?
// graveyard?
