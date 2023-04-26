@LAZYGLOBAL OFF.

{
	LOCAL s IS STACK().
	LOCAL lookup IS LEXICON().
	
	GLOBAL Import IS {
		PARAMETER n. // e.g. "someprogram.ks"
		//PRINT "Importing " + n.
		s:PUSH(n).
		IF NOT EXISTS("1:/"+n) COPYPATH("0:/"+n,"1:/"+n).
		RUNPATH("1:/"+n).
		RETURN lookup[n].
	}.
	
	GLOBAL Export IS {
		PARAMETER val.
		LOCAL fn IS s:POP().
		//PRINT "Exporting " + fn.
		SET lookup[fn] TO val.
	}.
	
	GLOBAL MISSION_ABORT IS FALSE.
	ABORT OFF.

}