@LAZYGLOBAL OFF.

{
	// do an event, if possible
	// return true/false if it happened/not
	LOCAL FUNCTION DO_EVENT {
		PARAMETER partTag,
				  moduleName,
				  eventName,
				  isSingleton,
				  debug IS FALSE.
		
		LOCAL success IS FALSE.
		
		IF NOT SHIP:PARTSTAGGED(partTag):EMPTY {
			IF SHIP:PARTSTAGGED(partTag)[0]:HASMODULE(moduleName) {
				IF SHIP:PARTSTAGGED(partTag)[0]:GETMODULE(moduleName):HASEVENT(eventName) {
					IF isSingleton {
						SHIP:PARTSTAGGED(partTag)[0]:GETMODULE(moduleName):DOEVENT(eventName).
					} ELSE {
						FOR p in SHIP:PARTSTAGGED(partTag) {
							p:GETMODULE(moduleName):DOEVENT(eventName).
						}
					}
					SET success TO TRUE.
				} ELSE { // didn't have the event
					IF debug {
						// print the available events:
						FOR n IN SHIP:PARTSTAGGED(partTag)[0]:GETMODULE(moduleName):ALLEVENTS {
							PRINT "Found event: " + n + " for module: " + moduleName.
						}
					}
				}
			} ELSE { // didn't have the module
				IF debug {
					// print the available modules:
					FOR n IN SHIP:PARTSTAGGED(partTag)[0]:MODULES {
						PRINT "Found module: " + moduleName.
					}
				}
			}
		} ELSE { // part wasn't found with tag
			IF debug { PRINT "No part found with tag: " + partTag. }
		}
		
		RETURN success.
	}









	// export the "public" members
	LOCAL this IS LEXICON(
		"DO_EVENT", DO_EVENT@
	).
	
	Export(this).

}
