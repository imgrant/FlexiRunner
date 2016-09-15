class FlexiRunnerApp extends Toybox.Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    //! Return the initial view of your application here
    function getInitialView() {
        return [ new FlexiRunnerView() ];
    }

}


class FlexiRunnerView extends Toybox.WatchUi.DataField {

	var hrZones;
	hidden var timerDisplayLimit = 3599;	//! If the timer is less than this, display it as mm:ss, otherwise h:mm(ss). Two values make sense: 3599 for 59:59 or 5999 for 99:59
	var unitP;
	var unitD;

	enum {
		TOP_ROW_TIMER_DISTANCE,
		TOP_ROW_DISTANCE_TIMER
	}
	hidden var topRowDisplay = TOP_ROW_TIMER_DISTANCE;	//! Top row display, timer on the left, distance on the right, or the reverse

	hidden enum {
		HR_DISPLAY_BPM,
		HR_DISPLAY_ZONE,
		HR_DISPLAY_BOTH
	}
	hidden var hrDisplay = HR_DISPLAY_BPM;	//! Show heart rate as direct bpm, zone decimal (e.g. 3.5), or both

	hidden enum {
		PACE_AVERAGE,
		PACE_MOVING,
		PACE_LAP,
		PACE_LAP_MOVING,
		PACE_LAST_LAP,
		PACE_LAST_LAP_MOVING	
	}
	hidden var bottomLeftData = PACE_MOVING;	//! Data to show in bottom left field
	hidden var bottomRightData = PACE_AVERAGE;	//! Data to show in bottom right field
	
	hidden var mActivityInfo;
	var mTimerRunning = false;

	var hrZone = 0.0;
	hidden var targetSpeed = 0.0;
	
	hidden var stoppedSeconds = 0;
	hidden var movingSpeed = 0.0;

	hidden var targetPaceMetric = PACE_AVERAGE;	//! Which average pace metric should be used as the reference for deviation of the current pace? (see above)
	hidden var paceDeviation = null;

	var laps = 1;
	var lastLapDistMarker = 0.0;
    var lastLapTimeMarker = 0;

    var lapTimerTime = 0;
	var lapStoppedSeconds = 0;
	var lapMovingSpeed = 0.0;
	var lapElapsedDistance = 0.0;
	var lapSpeed = 0.0;

	var lastLapTimerTime = 0;
	var lastLapStoppedSeconds = 0;
	var lastLapMovingSpeed = 0.0;
	var lastLapElapsedDistance = 0.0;
	var lastLapSpeed = 0.0;
   

    function initialize() {
        DataField.initialize();  
        
 		hrZones = UserProfile.getHeartRateZones(UserProfile.getCurrentSport());
 		topRowDisplay		= Application.getApp().getProperty("TopRowConfig");
 		hrDisplay 			= Application.getApp().getProperty("HrConfig");	 
 		targetPaceMetric	= Application.getApp().getProperty("TargetPace");
 
 		
        if (System.getDeviceSettings().paceUnits == System.UNIT_METRIC) {
        	unitP = 1000.0;
        } else { //if (System.getDeviceSettings().paceUnits == System.UNIT_STATUTE) {
        	unitP = 1609.344;
        }
        
        if (System.getDeviceSettings().distanceUnits == System.UNIT_METRIC) {
        	unitD = 1000.0;
        } else { //if (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE) {
        	unitD = 1609.344;
        }

    }

    //! Set your layout here. Anytime the size of obscurity of
    //! the draw context is changed this will be called.
    function onLayout(dc) {
    }


    //! The given info object contains all the current workout
    //! information. Calculate a value and save it locally in this method.
    function compute(info) {

    	mActivityInfo = info;

		if (info.timerTime != null) {
			//! N.B. info.timerTime is converted from milliseconds to seconds here
			mActivityInfo.timerTime = info.timerTime / 1000;
			lapTimerTime 			= mActivityInfo.timerTime - lastLapTimeMarker;
		} else {
			mActivityInfo.timerTime = 0;
			lapTimerTime 			= 0;			
		}
    	
    	if (info.currentSpeed != null) {
    		mActivityInfo.currentSpeed = info.currentSpeed;
    	} else {
    		mActivityInfo.currentSpeed = 0.0;
    	}

    	if (mTimerRunning && mActivityInfo.currentSpeed < 1.75) { //! Speed below which the moving time timer is paused (1.75 m/s = 9:30 min/km)
			//! Simple non-moving time calculation - relies on compute() being called every second
			stoppedSeconds++;
			lapStoppedSeconds++;
		}

    	
    	if (info.currentHeartRate != null) {
			if (hrZones != null) {		
		    	if (mActivityInfo.currentHeartRate < hrZones[0]) {
					hrZone = mActivityInfo.currentHeartRate / hrZones[0].toFloat();
				} else if (mActivityInfo.currentHeartRate < hrZones[1]) {
					hrZone = 1 + (mActivityInfo.currentHeartRate - hrZones[0]) / (hrZones[1] - hrZones[0]).toFloat();
				} else if (mActivityInfo.currentHeartRate < hrZones[2]) {
					hrZone = 2 + (mActivityInfo.currentHeartRate - hrZones[1]) / (hrZones[2] - hrZones[1]).toFloat();
				} else if (mActivityInfo.currentHeartRate < hrZones[3]) {
					hrZone = 3 + (mActivityInfo.currentHeartRate - hrZones[2]) / (hrZones[3] - hrZones[2]).toFloat();
				} else if (mActivityInfo.currentHeartRate < hrZones[4]) {
					hrZone = 4 + (mActivityInfo.currentHeartRate - hrZones[3]) / (hrZones[4] - hrZones[3]).toFloat();
				} else {
					hrZone = 5 + (mActivityInfo.currentHeartRate - hrZones[4]) / (hrZones[5] - hrZones[4]).toFloat();
				}
			} else {
				hrZone = 0.0;
			}
    	} else {
    		mActivityInfo.currentHeartRate = 0;
    		hrZone = 0.0;
    	}
    		
    	if (info.currentCadence == null) {
    		mActivityInfo.currentCadence = 0;
    	}    	
    	
    	if (info.elapsedDistance != null) {
			lapElapsedDistance 	= mActivityInfo.elapsedDistance - lastLapDistMarker;
    	} else {
    		mActivityInfo.elapsedDistance = 0.0;
    		lapElapsedDistance 	= 0;
    	}
    	
    	if (lapTimerTime > 1000 && lapElapsedDistance > 0) {
    		lapSpeed = lapElapsedDistance / lapTimerTime;
    	} else {
    		lapSpeed = 0.0;
    	}

    	if (info.averageSpeed == null) {
    		mActivityInfo.averageSpeed = 0.0;
    	}
    	
    	if (stoppedSeconds == 0) {
    		movingSpeed = mActivityInfo.averageSpeed;
    	} else {
	    	if (mActivityInfo.timerTime > 0 && stoppedSeconds < mActivityInfo.timerTime) {
	    		movingSpeed = mActivityInfo.elapsedDistance / (mActivityInfo.timerTime - stoppedSeconds);
	    	} else {
	    		movingSpeed = mActivityInfo.averageSpeed;
	    	}
    	}
    	if (lapStoppedSeconds == 0) {
    		lapMovingSpeed = lapSpeed;
    	} else {
	    	if (lapTimerTime > 0 && lapStoppedSeconds < lapTimerTime) {
	    		lapMovingSpeed = lapElapsedDistance / (lapTimerTime - lapStoppedSeconds);
	    	} else {
	    		lapMovingSpeed = lapSpeed;
	    	}
    	}
    	
    	if (targetPaceMetric == PACE_AVERAGE) {
			targetSpeed = mActivityInfo.averageSpeed;
		} else if (targetPaceMetric == PACE_MOVING) {
			targetSpeed = movingSpeed;
		} else if (targetPaceMetric == PACE_LAP) {
			targetSpeed = lapSpeed;
		} else if (targetPaceMetric == PACE_LAP_MOVING) {
			targetSpeed = lapMovingSpeed;
		} else if (targetPaceMetric == PACE_LAST_LAP) {
			targetSpeed = lastLapSpeed;
		} else if (targetPaceMetric == PACE_LAST_LAP_MOVING) {
			targetSpeed = lastLapMovingSpeed;
		}
					
		if (targetSpeed > 0.0 && mActivityInfo.currentSpeed > 0.0) {
			paceDeviation = (mActivityInfo.currentSpeed / targetSpeed);
		} else {
			paceDeviation = null;
		}
/*		
		var stats = System.getSystemStats();
        var memUsed = stats.usedMemory.toString();
        var memTotal = stats.totalMemory.toString();
        var memFree = stats.freeMemory.toString();
        System.println("==================================================");
        System.println("Memory usage: " + memUsed + " / " + memTotal + " (" + memFree + " free)");
		System.println("Timer: " + mActivityInfo.timerTime);
		System.println("Stopped seconds: " + stoppedSeconds);
		System.println("Distance: " + mActivityInfo.elapsedDistance);
		System.println("Current speed: " + mActivityInfo.currentSpeed);
		System.println("Average speed: " + mActivityInfo.averageSpeed);
		if (paceDeviation != null) {
			System.println("Pace deviation: " + (paceDeviation * 100).format("%d") + "%");
		} else {
			System.println("Pace deviation: N/A");
		}
		System.println("Moving average speed: " + movingSpeed);
		System.println("Current heart rate: " + mActivityInfo.currentHeartRate);
		System.println("Current heart rate zone: " + hrZone);
		System.println("Current cadence: " + mActivityInfo.currentCadence);
		System.println("Laps: " + laps);
		System.println("Lap timer: " + lapTimerTime);
		System.println("Lap stopped seconds: " + lapStoppedSeconds);
		System.println("Lap distance: " + lapElapsedDistance);
		System.println("Lap speed: " + lapSpeed);
		System.println("Lap moving speed: " + lapMovingSpeed);
		System.println("Last lap timer: " + lastLapTimerTime);
		System.println("Last lap stopped seconds: " + lastLapStoppedSeconds);
		System.println("Last lap distance: " + lastLapElapsedDistance);
		System.println("Last lap speed: " + lastLapSpeed);
		System.println("Last lap moving speed: " + lastLapMovingSpeed);
		System.println("==================================================");
/**/
    }

    //! Store last lap quantities and set lap markers
    function onTimerLap() {
    	lastLapTimerTime		= lapTimerTime;
    	lastLapStoppedSeconds	= lapStoppedSeconds;
    	lastLapElapsedDistance	= lapElapsedDistance;
    	lastLapSpeed			= lapSpeed;
    	lastLapMovingSpeed		= lapMovingSpeed;
    	laps++;
    	lastLapDistMarker 		= mActivityInfo.elapsedDistance;
    	lastLapTimeMarker 		= mActivityInfo.timerTime;
    	lapStoppedSeconds 		= 0;
    }

    //! Timer transitions from stopped to running state
    function onTimerStart() {
    	mTimerRunning = true;
    }


    //! Timer transitions from running to stopped state
    function onTimerStop() {
    	mTimerRunning = false;
    }


    //! Timer transitions from paused to running state (i.e. resume from Auto Pause is triggered)
    function onTimerResume() {
    	mTimerRunning = true;
    }


    //! Timer transitions from running to paused state (i.e. Auto Pause is triggered)
    function onTimerPause() {
    	mTimerRunning = false;
    }


    //! Display the value you computed here. This will be called
    //! once a second when the data field is visible.
    function onUpdate(dc) {
    	dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.clear();    	

    	//! Draw the HR field separator (if applicable) first, underneath the indicators
    	if (hrDisplay == HR_DISPLAY_BOTH) {
    		dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_WHITE);
        	dc.setPenWidth(2);
        	dc.drawLine(0, 90, 54, 90);
    	}

    	//!
    	//! Draw colour indicators first	
    	//!	
		dc.setPenWidth(16);

		//! Set HR zone indicator colour
		if (hrZone < 1.0) {
    		dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);	//! No zone
		} else if (hrZone < 2.0) {
			dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);	//! Warm-up
		} else if (hrZone < 3.0) {
			dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);		//! Easy
		} else if (hrZone < 4.0) {
			dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);		//! Aerobic
		} else if (hrZone < 5.0) {
			dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);		//! Threshold
		} else {
			dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);		//! Maximum
		}
		dc.drawArc(111, 89, 106, dc.ARC_CLOCKWISE, 200, 158);	

		//! Set cadence zone indicator colour (fixed thresholds and colours to match Garmin, with the addition of grey for walking/stopped)
		if (mActivityInfo.currentCadence > 183) {
			dc.setColor(Graphics.COLOR_PURPLE, Graphics.COLOR_TRANSPARENT);
		} else if (mActivityInfo.currentCadence >= 174) {
			dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
		} else if (mActivityInfo.currentCadence >= 164) {
			dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
		} else if (mActivityInfo.currentCadence >= 153) {
			dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
		} else if (mActivityInfo.currentCadence >= 130) {
			dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
		}  else {
			dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
		}
		dc.drawArc(103, 89, 106, dc.ARC_CLOCKWISE, 20, 340);

		//! Current pace vs (moving) average pace colour indicator
		if (paceDeviation == null) {
			dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
		} else if (paceDeviation < 0.95) {	//! Maximum % slower deviation of current pace from target considered good
			dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
		} else if (paceDeviation <= 1.05) {	//! Maximum % faster deviation of current pace from target considered good
			dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
		} else {
			dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
		}
		dc.fillRectangle(54, 56, 107, 18);			
		//! Chop tops and bottoms off arcs
		dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
		dc.fillRectangle(0, 48, 215, 8);
		dc.fillRectangle(0, 121, 215, 8);

    	//! Draw separator lines
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_WHITE);
        dc.setPenWidth(2);
        //! Horizontal thirds
		dc.drawLine(0, 56, 215, 56);
		dc.drawLine(0, 121, 215, 121);
		//! Top vertical divider adjustment - timer on the left, distance on the right: shift the divider to the right slightly if displaying additional seconds field for the timer
		if (mActivityInfo.timerTime > timerDisplayLimit) {
			dc.drawLine(120, 0, 120, 56);
		} else {
			//! Distance on the left, timer on the right, and/or when not showing additional seconds
			dc.drawLine(107, 0, 107, 56);
		}
		//! Centre vertical dividers
		dc.drawLine(54, 56, 54, 121);
		dc.drawLine(161, 56, 161, 121);
		//! Bottom vertical divider
		dc.drawLine(107, 121, 107, 180);
		
          
        //!
        //! Draw fields
        //! ===========
        //!
              
        //! Set text colour
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);

        var fDistance;
        if ((mActivityInfo.elapsedDistance/unitD) < 100) {
			fDistance = (mActivityInfo.elapsedDistance/unitD).format("%.2f");
		} else {
			fDistance = (mActivityInfo.elapsedDistance/unitD).format("%.1f");
		}

		var fTimerHours 	= (mActivityInfo.timerTime / 3600).format("%d");
		var fTimerMins 		= (mActivityInfo.timerTime / 60 % 60).format("%02d");
		var fTimerSecs 		= (mActivityInfo.timerTime % 60).format("%02d");
		var fTimerMinsAbs 	= (mActivityInfo.timerTime / 60).format("%d");
        //! Top row: timer and distance
        if (topRowDisplay == TOP_ROW_TIMER_DISTANCE) {
	    	//! Timer on the left, distance on the right - additional seconds on timer causes distance field to be compressed  	
			if (mActivityInfo.timerTime > timerDisplayLimit) {
				//! Format time as h:mm(ss)
				dc.drawText(26, 34, Graphics.FONT_NUMBER_MEDIUM, fTimerHours + ":" + fTimerMins, Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
				dc.drawText(89, 26, Graphics.FONT_NUMBER_MILD, fTimerSecs, Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
				if ((mActivityInfo.elapsedDistance/unitD) >= 10.0) {
					dc.drawText(171, 34, Graphics.FONT_NUMBER_MEDIUM, (mActivityInfo.elapsedDistance/unitD.toLong()).format("%d") + ".", Graphics.TEXT_JUSTIFY_RIGHT|Graphics.TEXT_JUSTIFY_VCENTER);
					dc.drawText(175, 40, Graphics.FONT_NUMBER_MILD, (mActivityInfo.elapsedDistance.toLong() % unitD.toLong() / unitD * 100).format("%02d"), Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
				} else {
					dc.drawText(159, 34, Graphics.FONT_NUMBER_MEDIUM, fDistance, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
				}
				dc.drawText(131, 8, Graphics.FONT_XTINY,  "Dist.", Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
			} else {
				//! Format time as m:ss
				dc.drawText(64, 34, Graphics.FONT_NUMBER_MEDIUM, fTimerMinsAbs + ":" + fTimerSecs, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
				dc.drawText(151, 34, Graphics.FONT_NUMBER_MEDIUM, fDistance, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
				dc.drawText(117, 8, Graphics.FONT_XTINY,  "Distance", Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
			}	
			dc.drawText(50, 8, Graphics.FONT_XTINY,  "Timer", Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);	
		} else if (topRowDisplay == TOP_ROW_DISTANCE_TIMER) {
			//! Distance on the left, timer on the right - additional seconds on timer positioned at baseline, no changes needed to distance field
			dc.drawText(62, 34, Graphics.FONT_NUMBER_MEDIUM, fDistance, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(70, 8, Graphics.FONT_XTINY,  "Distance", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			if (mActivityInfo.timerTime > timerDisplayLimit) {
				dc.drawText(1113, 34, Graphics.FONT_NUMBER_MEDIUM, fTimerHours + ":" + fTimerMins, Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
				dc.drawText(176, 39, Graphics.FONT_NUMBER_MILD, fTimerSecs, Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
			} else {
				dc.drawText(151, 34, Graphics.FONT_NUMBER_MEDIUM, fTimerMinsAbs + ":" + fTimerSecs, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			}	
			dc.drawText(141, 8, Graphics.FONT_XTINY,  "Timer", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}
			
		if (mActivityInfo.currentSpeed < 0.447164) {
			dc.drawLine(81, 116, 103, 116);
			dc.drawLine(58, 116, 80, 116);
			dc.drawLine(111, 116, 133, 116);
			dc.drawLine(134, 116, 156, 116);
			dc.drawText(107, 98, Graphics.FONT_NUMBER_MEDIUM, ":", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		} else {
			dc.drawText(106, 95, Graphics.FONT_NUMBER_HOT, fmtPaceRound5(mActivityInfo.currentSpeed), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}    	
		dc.drawText(107, 64, Graphics.FONT_XTINY,  "Pace", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		
		//! Centre left: heart rate
		var hrNudge = 0;
		var hrBpm = (mActivityInfo.currentHeartRate > 0) ? mActivityInfo.currentHeartRate : "--";
		if (mActivityInfo.currentHeartRate < 100) {
			hrNudge = 2;
		} else {
			hrNudge = 0;
		}
		if (hrDisplay == HR_DISPLAY_BOTH) {			
			dc.drawText(32 + hrNudge, 72, Graphics.FONT_NUMBER_MILD, hrBpm, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(34, 104, Graphics.FONT_NUMBER_MILD, hrZone.format("%.1f"), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(6, 81, Graphics.FONT_XTINY, "H", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(6, 94, Graphics.FONT_XTINY, "R", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		} else if (hrDisplay == HR_DISPLAY_ZONE) {
			dc.drawText(33, 98, Graphics.FONT_NUMBER_MILD, hrZone.format("%.1f"), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(35, 71, Graphics.FONT_XTINY, "HR Z.", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		} else { //if (hrDisplay == HR_DISPLAY_BPM) {
			dc.drawText(32 + hrNudge, 98, Graphics.FONT_NUMBER_MILD, hrBpm, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(33, 71, Graphics.FONT_XTINY, "HR", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}
		
		//! Centre right: cadence
    	dc.drawText(179, 98, Graphics.FONT_NUMBER_MILD, mActivityInfo.currentCadence, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		dc.drawText(180, 71, Graphics.FONT_XTINY,  "Cad.", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
	
		//! Bottom left: average moving pace
		if (movingSpeed < 0.447164) {
			dc.drawLine(26, 156, 43, 156);
			dc.drawLine(44, 156, 61, 156);
			dc.drawLine(69, 156, 86, 156);
			dc.drawLine(87, 156, 104, 156);
			dc.drawText(65, 138, Graphics.FONT_NUMBER_MEDIUM, ":", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		} else {
			dc.drawText(60, 141, Graphics.FONT_NUMBER_MEDIUM, fmtPace(movingSpeed), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}
		dc.drawText(102, 167, Graphics.FONT_XTINY,  "Run. Pace", Graphics.TEXT_JUSTIFY_RIGHT|Graphics.TEXT_JUSTIFY_VCENTER);
			
		//! Bottom right: overall average pace
		if (mActivityInfo.averageSpeed < 0.447164) {
			dc.drawLine(111, 156, 128, 156);
			dc.drawLine(129, 156, 146, 156);
			dc.drawLine(154, 156, 171, 156);
			dc.drawLine(172, 156, 189, 156);
			dc.drawText(150, 138, Graphics.FONT_NUMBER_MEDIUM, ":", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		} else {
			dc.drawText(150, 141, Graphics.FONT_NUMBER_MEDIUM, fmtPace(mActivityInfo.averageSpeed), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}
		dc.drawText(111, 167, Graphics.FONT_XTINY,  "Avg. Pace", Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);

    }
        
    
    function fmtPace(secs) {
        return ((unitP/secs).toLong() / 60).format("%0d") + ":" + ((unitP/secs).toLong() % 60).format("%02d");
    }
    

    function fmtPaceRound5(secs) {
        return fmtPace(unitP/(Math.round((unitP/secs) / 5) * 5));
    }

}
