@LAZYGLOBAL OFF.

{
	GLOBAL RUNMODE IS "1:/runmode.ks".
	
	Export( {
		PARAMETER mdf. // mission delegate function
		
		LOCAL rm IS 0.	// the current runmode?
		IF EXISTS(RUNMODE) SET rm TO Import("runmode.ks"). // has the mission already started?
		
		LOCAL seq IS LIST().		// mission sequence
		LOCAL evlx IS LEXICON().	// mission events
		
		// delegate for mission Next
		LOCAL n IS {
			PARAMETER m IS rm+1.
			IF NOT EXISTS(RUNMODE) CREATE(RUNMODE).
			LOCAL h IS open(RUNMODE).
			h:clear().
			h:write("export("+m+").").
			SET rm TO m.
		}.
		
		// run the delegate function
		mdf(seq, evlx, n).  // e.g. mission(sequence, events, next).

		// send back a delegate which gets us the current runmode
		// until we get to the end of the mission sequence
		RETURN {
			UNTIL rm >= seq:LENGTH { 
				SET MISSION_ABORT TO ABORT.
				FOR val IN evlx:VALUES val().				
				seq[rm]().
				WAIT 0.
			}
		}.
	}).
}