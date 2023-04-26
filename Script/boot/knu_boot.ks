@LAZYGLOBAL OFF.

// FOR TESTING
SWITCH TO 1.
FOR f IN LIST (
	"knu.ks",
	"mission.ks",
	"m_example.ks",
	"transfer.ks",
	"descent.ks"
) DELETEPATH("1:/" + f).


IF NOT EXISTS("1:/knu.ks") COPYPATH("0:/knu.ks", "1:/").

RUNPATH("1:/knu.ks"). 
IMPORT("m_example.ks")().