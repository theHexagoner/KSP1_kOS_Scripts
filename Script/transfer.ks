@LAZYGLOBAL OFF.

{
	LOCAL INFINITY IS 2^64.

	LOCAL tranzfer IS LEXICON(
		"Exec", Exec@,
		"Freeze", Freeze@,
		"Seek_SOI", Seek_SOI@,
		"Seek", Seek@,
		"Node_For_AP", Node_For_AP@,
		"Node_For_PE", Node_For_PE@,
		"GET_BURNTIME", GetBurntime@
	).

	LOCAL FUNCTION Exec {
		PARAMETER nn IS NEXTNODE.
				  
		LOCAL ts_Start IS TIME:SECONDS + nn:ETA - GetBurntime(nn:BURNVECTOR:MAG):MEAN.
		
		LOCAL prevSAS TO SAS.
		LOCAL prevRCS TO RCS.
		
		LOCAL dv0 IS nn:DELTAV.
		LOCAL dvMin IS dv0:MAG.
		LOCAL minThrottle IS 0.
		LOCAL maxThrottle IS 0.
		LOCAL almostThere IS 0.

		WAIT UNTIL TIME:SECONDS >= ts_Start -30.
		
		LOCK THROTTLE TO MIN(maxThrottle, MAX(minThrottle, MIN(dvMin, nn:DELTAV:MAG) * SHIP:MASS / MAX(1, SHIP:AVAILABLETHRUST))).
		LOCK STEERING TO LOOKDIRUP(nn:DELTAV, SHIP:POSITION - BODY:POSITION).

		WAIT UNTIL TIME:SECONDS >= ts_Start.

		UNTIL dvMin < 0.05 {
			WAIT 0. 
	
			LOCAL dv IS nn:DELTAV:MAG.
			IF dv < dvMin SET dvMin TO dv.
	
			IF SHIP:AVAILABLETHRUST > 0 {
				SET minThrottle TO 0.01.
				SET maxThrottle TO 1.
		
				IF VDOT(dv0, nn:deltaV) < 0 BREAK. // overshot (node delta vee is pointing opposite from initial)
				
				IF dv > dvMin + 0.1 BREAK. // burn DV increases (off target due to wobbles)
				
				IF dv <= 0.2 { // burn DV gets too small for main engines to cope with
					IF almostThere = 0 SET almostThere TO TIME:SECONDS.
					IF TIME:SECONDS - almostThere > 5 BREAK.
					IF dv <= 0.05 BREAK.
				}
			}
		}
	
		SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
		UNLOCK THROTTLE.
	
		// let RCS do the rest, if necessary
		IF nn:DELTAV:MAG > 0.1 {
		
		} ELSE {
			WAIT 1.
		}

		// REPORT success/fail?

		REMOVE nn.
	
		// release all controls to be safe:
		
		UNLOCK STEERING.
		UNLOCK THROTTLE.
		SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
		SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
	
		SET SAS TO prevSAS.
		SET RCS TO prevRCS.
	}

	LOCAL FUNCTION Freeze {
		PARAMETER n. 
		RETURN LEXICON("Frozen", n).
	}

	LOCAL FUNCTION Seek {
		PARAMETER ts, 	// timestamp	
				  rad, 	// radial dV
				  nrm,  // normal dv
				  pro,  // prograde dv
				  fitFunc,	// a fitness function by which to evaluate the proposed mnv node
				  data IS LIST(ts, rad, nrm, pro), // store the values of the mnv
				  fit IS Orbit_Fitness(fitFunc@).  // score it?
    
		SET data TO Optimize(data, fit, 100).
		SET data TO Optimize(data, fit, 10).
		SET data TO Optimize(data, fit, 1).
		fit(data). 
		WAIT 0. 
		RETURN data.
	}

	LOCAL FUNCTION Seek_SOI {
		PARAMETER target_body, 
			      target_periapsis,
                  start_time IS TIME:SECONDS + 600.

		LOCAL data IS Seek(start_time, 0, 0, 1000, {
			PARAMETER mnv.
			IF Transfers_To(mnv:ORBIT, target_body) RETURN 1.
			
			RETURN -Closest_Approach(target_body, TIME:SECONDS + mnv:ETA, TIME:SECONDS + mnv:ETA + mnv:ORBIT:period).
		}).

		RETURN Seek(data[0], data[1], data[2], data[3], {
			PARAMETER mnv.
			IF NOT Transfers_To(mnv:ORBIT, target_body) RETURN -INFINITY.
			IF TIME:SECONDS + mnv:ETA < start_time RETURN -INFINITY.
						 
			RETURN -ABS(mnv:ORBIT:NEXTPATCH:PERIAPSIS - target_periapsis).
		}).
	}

	LOCAL FUNCTION Transfers_To {
		PARAMETER target_orbit, 
				  target_body.
		RETURN (target_orbit:HASNEXTPATCH AND target_orbit:NEXTPATCH:BODY = target_body).
	}

	LOCAL FUNCTION Closest_Approach {
		PARAMETER target_body, 
				  start_time, 
				  end_time.
				  
		LOCAL start_slope IS Slope_At(target_body, start_time).
		LOCAL end_slope IS Slope_At(target_body, end_time).
		LOCAL middle_time IS (start_time + end_time) / 2.
		LOCAL middle_slope IS Slope_At(target_body, middle_time).
    
		UNTIL (end_time - start_time < 0.1) OR middle_slope < 0.1 {
			IF (middle_slope * start_slope) > 0
				SET start_time TO middle_time.
			ELSE
				SET end_time TO middle_time.
      
			SET middle_time TO (start_time + end_time) / 2.
			SET middle_slope TO Slope_At(target_body, middle_time).
		}
		RETURN Separation_At(target_body, middle_time).
	}

	LOCAL FUNCTION Slope_At {
		PARAMETER target_body, 
				  at_time.
		RETURN ( Separation_At(target_body, at_time + 1) - Separation_At(target_body, at_time - 1) ) / 2.
	}

	LOCAL FUNCTION Separation_At {
		PARAMETER target_body, 
				  at_time.
		RETURN (POSITIONAT(SHIP, at_time) - POSITIONAT(target_body, at_time)):MAG.
	}


	// Calculates when in time the mean of a given burn is done. 
	// For example a 10s burn with constant acceleration will have a burn mean of 5s.
	// With constantly rising acceleration it would be closer to 7s.
	// Line up the burn mean with the maneuver node to hit the targeted change with accuracy 
	LOCAL FUNCTION GetBurntime {
		PARAMETER dV. // delta v of mnv
		
		LOCAL F IS 0.
		LOCAL si IS 0.
		LOCAL ct IS 0.
		
		LOCAL all_engines IS LIST().
		LIST ENGINES IN all_engines.
		
		FOR n IN all_engines IF n:IGNITION AND NOT n:FLAMEOUT {
			SET F TO F + n:AVAILABLETHRUST.
			SET si TO si + n:ISP.
			SET ct TO ct + 1.
        }
	
		SET si TO si/ct.

		// mass flow
		LOCAL m_d TO F / (si * 9.81).
	
		// starting mass
		LOCAL m_0 TO SHIP:MASS.
	
		// calculate burn time
		LOCAL t_1 TO - (CONSTANT:E^(ln(m_0)-(dV*m_d)/F)-m_0)/m_d.
	
		// calculate mean burn time
		LOCAL t_m TO (m_0*ln((m_d*t_1-m_0)/-m_0)+m_d*t_1)/(m_d*ln((m_0-m_d*t_1)/m_0)).
	
		RETURN LEXICON("MEAN", t_m, "TOTAL", t_1).
	}


	// create and add a node for adjusting PE
	LOCAL FUNCTION Node_For_PE {
		PARAMETER desiredPeriapsis.
		PARAMETER nodeTime IS TIME:SECONDS + ETA:APOAPSIS.		
		RETURN Node_Alt(desiredPeriapsis, nodeTime).
	}

	// create and add a node for adjusting AP
	LOCAL FUNCTION Node_For_AP {
		PARAMETER desiredApoapsis.
		PARAMETER nodeTime IS TIME:SECONDS + ETA:PERIAPSIS.
		RETURN Node_Alt(desiredApoapsis, nodeTime).
	}

	// create a node for adjusting altitude 
	LOCAL FUNCTION Node_Alt {
		PARAMETER desiredAltitude.
		PARAMETER nodeTime IS TIME:SECONDS + 120.

		LOCAL mu IS BODY:MU.
		LOCAL br IS BODY:RADIUS.

		// present orbit properties
		LOCAL vom IS SHIP:VELOCITY:ORBIT:MAG. 	// current velocity
		LOCAL r1 IS br + SHIP:ALTITUDE. 		// current radius
		LOCAL v1 IS VELOCITYAT(SHIP, nodeTime):ORBIT:MAG. // velocity at burn time
		LOCAL sma1 IS ORBIT:SEMIMAJORAXIS.

		// future orbit properties
		LOCAL r2 IS br + SHIP:BODY:ALTITUDEOF(POSITIONAT(SHIP, nodeTime)).
		LOCAL sma2 IS (desiredAltitude + br + r2) / 2.
		LOCAL v2 IS sqrt( vom ^ 2 + (mu * (2 / r2 - 2 / r1 + 1 / sma1 - 1 / sma2 ) ) ).

		// create node
		LOCAL dv IS v2 - v1.
		LOCAL nd IS NODE(nodeTime, 0, 0, dv).
		ADD nd.	
	}



	LOCAL FUNCTION Orbit_Fitness {
		PARAMETER fitness.
    
		RETURN {
			PARAMETER data.
			UNTIL NOT HASNODE { REMOVE NEXTNODE. WAIT 0. }
      
			LOCAL new_node IS NODE(Unfreeze(data[0]), Unfreeze(data[1]), Unfreeze(data[2]), Unfreeze(data[3])).
			ADD new_node.
			WAIT 0.
			RETURN fitness(new_node).
		}.
	}

	LOCAL FUNCTION Optimize {
		PARAMETER data, 
				  fitness, 
				  step_size,
				  winning IS LIST(fitness(data), data),
				  improvement IS Best_Neighbor(winning, fitness, step_size).
		
		UNTIL improvement[0] <= winning[0] {
			SET winning TO improvement.
			SET improvement TO Best_Neighbor(winning, fitness, step_size).
		}
		RETURN winning[1].
	}

	LOCAL FUNCTION Best_Neighbor {
		PARAMETER best, 
				  fitness, 
				  step_size.
    
		FOR neighbor IN Neighbors( best[1], step_size ) {
			LOCAL score IS fitness(neighbor).
			IF score > best[0] SET best TO LIST(score, neighbor).
		}
		
		RETURN best.
	}

	LOCAL FUNCTION Neighbors {
		PARAMETER data, 
				  step_size, 
				  results IS LIST().
    
		FOR i IN RANGE(0, data:LENGTH) IF NOT Frozen(data[i]) {
			LOCAL increment IS data:COPY.
			LOCAL decrement IS data:COPY.
			SET increment[i] TO increment[i] + step_size.
			SET decrement[i] TO decrement[i] - step_size.
			results:ADD(increment).
			results:ADD(decrement).
		}
		RETURN results.
	}

	LOCAL FUNCTION Frozen {
		PARAMETER val. 
		RETURN (val+""):INDEXOF("Frozen") <> -1.
	}

	LOCAL FUNCTION Unfreeze {
		PARAMETER val. 
		IF Frozen(val) RETURN val["Frozen"]. 
		ELSE RETURN val.
	}

	Export(tranzfer).
}