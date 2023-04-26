@LAZYGLOBAL OFF.

// Example Mission Script
// derived from KSProgramming - Cheers Kevin Games

// import some program files you  might need
LOCAL mission IS Import("mission").
LOCAL tranzfer IS Import("transfer").
LOCAL descent IS Import("descent").

// declare local vars for functions inside those programs
LOCAL freeze IS tranzfer["Freeze"].

// declare your mission (sequence and events)

LOCAL m_lv IS mission( { 
	PARAMETER seq, 		// mission sequence
			  evts,  	// mission events
			  goNext. 	// what happens next
	

	// add a step
	seq:ADD( {
		PRINT "This is a step in the mission sequence".
		WAIT 10. // countdown?
		
		// do the next thing
		goNext().
	}).

	// add another step
	seq:ADD( {
		PRINT "This is another step in the mission sequence".
		goNext().
	}).
	
	// do one more thing

	seq:ADD( {
		PRINT "This is the last step in the mission sequence".
		goNext().
	}).
	
	// TODO: add some example mission events?
	
}).

Export(m_lv).