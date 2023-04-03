@LAZYGLOBAL OFF.

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Stage 3 of the Soyuz lift vehicle, after separation from Progress/Soyuz spacecraft
//  load this -after- separation to be able to access the sepratrons via named variable                                                                                    ////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

GLOBAL sepratronsStageThree IS LIST().			// there are some separator engines on S3 to get it away

GLOBAL FUNCTION GetS3Ordinance {
	
	// get a reference to the stage 3 separators
	IF NOT SHIP:PARTSTAGGED("S3_SEPR"):EMPTY {
		SET sepratronsStageThree TO SHIP:PARTSTAGGED("S3_SEPR").
	}

	RETURN validateAll().
}

LOCAL FUNCTION validateAll {

	// check to make sure we've got all the references that are expected to be set for this program
	// if any of these fail, it generally means that our parts tags have not been set properly

	IF sepratronsStageThree:EMPTY {
		MissionLog("FAIL: Missing S3 ordinance").
        RETURN FALSE.
	}

	RETURN TRUE.
}





