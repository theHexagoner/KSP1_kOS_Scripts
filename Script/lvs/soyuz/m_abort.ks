@LAZYGLOBAL OFF.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  ABORT                                                                  		       									  //
//  This program will perform the abort logic for a mis-behaving Soyuz rocket                                             //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// get vehicle information in case this is result of unexpected reboot
RUNONCEPATH("lift_vehicle.ks").


PRINT "SELF DESTRUCT INITIATED".
	
// kill the engines
LOCK THROTTLE TO 0.0.	
	
// decouple from any spacecraft as they have their own abort logic
IF decouplerModuleStageThree:HASEVENT("DECOUPLE") {
	decouplerModuleStageThree:DOEVENT("Decouple").

	WAIT 0.1.
	RUNONCEPATH("S3.ks").
	WAIT 0.1.
	
	for s in sepratronsStageThree {
		s:ACTIVATE.
	}
}
	
IF selfDestructModule:ISTYPE("PartModule") {
	selfDestructModule:DOACTION("Self Destruct!", true).
}
