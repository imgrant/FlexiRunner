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

	hidden var hrZones;
	hidden var hrZone = 0.0;
	hidden var unitP;
	hidden var unitD;

	hidden var hrDisplay = 0;
	//! 0 => Direct heart rate in bpm
	//! 1 => Heart rate decimal zone (e.g. 3.5)
	//! 2 => Both bpm and zone

	hidden var bottomLeftData = 1;	//! Data to show in bottom left field
	hidden var bottomRightData = 0;	//! Data to show in bottom right field
	//! Paces enum:
	//! 0 => (overall) average pace
	//! 1 => Moving (running) pace
	//! 2 => Lap pace
	//! 3 => Lap moving (running) pace
	//! 4 => Last lap pace
	//! 5 => Last lap moving (running) pace

	hidden var timerDisplayLimit = 3599;	//! If the timer is less than this, display it as mm:ss, otherwise h:mm(ss). Two values make sense: 3599 for 59:59 or 5999 for 99:59
	
	hidden var mTimerRunning = false;
	
	hidden var stoppedSeconds = 0;
	hidden var movingSpeed = 0.0;

	hidden var targetSpeed = 0.0;
	hidden var targetPaceMetric = 0;	//! Which average pace metric should be used as the reference for deviation of the current pace? (see above)
	hidden var paceDeviation = null;

	hidden var mTimerTime = 0;
	hidden var mElapsedTime = 0;
	hidden var mElapsedDistance = 0.0;
	hidden var mCurrentSpeed = 0.0;	
	hidden var mAverageSpeed = 0.0;
	hidden var mCurrentHeartRate = 0;
	hidden var mCurrentCadence = 0;

	hidden var laps = 1;
	hidden var lastLapDistMarker = 0.0;
    hidden var lastLapTimeMarker = 0;

    hidden var lapTimerTime = 0;
	hidden var lapStoppedSeconds = 0;
	hidden var lapMovingSpeed = 0.0;
	hidden var lapElapsedDistance = 0.0;
	hidden var lapSpeed = 0.0;

	hidden var lastLapTimerTime = 0;
	hidden var lastLapMovingSpeed = 0.0;
	hidden var lastLapElapsedDistance = 0.0;
	hidden var lastLapSpeed = 0.0;
   

    function initialize() {
        DataField.initialize();  
        
 		hrZones = UserProfile.getHeartRateZones(UserProfile.getCurrentSport());
 		var mApp = Application.getApp();
 		hrDisplay 				= 1;//mApp.getProperty("HrConfig");	 
 		targetPaceMetric		= mApp.getProperty("TargetPace");
 		bottomLeftData			= mApp.getProperty("BottomLeftConfig");
 		bottomRightData			= mApp.getProperty("BottomRightConfig");
 		timerDisplayLimit		= mApp.getProperty("TimerDisplayLimit");
 
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


    //! The given info object contains all the current workout
    //! information. Calculate a value and save it locally in this method.
    function compute(info) {

		if (info.timerTime != null) {
			//! N.B. info.timerTime is converted from milliseconds to seconds here
			mTimerTime = info.timerTime / 1000;
			lapTimerTime = mTimerTime - lastLapTimeMarker;
		} else {
			mTimerTime = 0;
			lapTimerTime = 0;			
		}

		if (info.elapsedTime != null) {
			mElapsedTime = info.elapsedTime / 1000;
		} else {
			mElapsedTime = 0;
		}
    	
    	if (info.currentSpeed != null) {
    		mCurrentSpeed = info.currentSpeed;
    	} else {
    		mCurrentSpeed = 0.0;
    	}

    	if (mTimerRunning && mCurrentSpeed < 1.8) { //! Speed below which the moving time timer is paused (1.8 m/s = 9:15 min/km, ~15:00 min/mi)
			//! Simple non-moving time calculation - relies on compute() being called every second
			stoppedSeconds++;
			lapStoppedSeconds++;
		}

    	
    	if (info.currentHeartRate != null) {
    		mCurrentHeartRate = info.currentHeartRate;
			if (hrZones != null) {		
		    	if (mCurrentHeartRate < hrZones[0]) {
					hrZone = mCurrentHeartRate / hrZones[0].toFloat();
				} else if (mCurrentHeartRate < hrZones[1]) {
					hrZone = 1 + (mCurrentHeartRate - hrZones[0]) / (hrZones[1] - hrZones[0]).toFloat();
				} else if (mCurrentHeartRate < hrZones[2]) {
					hrZone = 2 + (mCurrentHeartRate - hrZones[1]) / (hrZones[2] - hrZones[1]).toFloat();
				} else if (mCurrentHeartRate < hrZones[3]) {
					hrZone = 3 + (mCurrentHeartRate - hrZones[2]) / (hrZones[3] - hrZones[2]).toFloat();
				} else if (mCurrentHeartRate < hrZones[4]) {
					hrZone = 4 + (mCurrentHeartRate - hrZones[3]) / (hrZones[4] - hrZones[3]).toFloat();
				} else {
					hrZone = 5 + (mCurrentHeartRate - hrZones[4]) / (hrZones[5] - hrZones[4]).toFloat();
				}
			} else {
				hrZone = 0.0;
			}
    	} else {
    		mCurrentHeartRate = 0;
    		hrZone = 0.0;
    	}
    		
    	if (info.currentCadence != null) {
    		mCurrentCadence = info.currentCadence;
    	} else {
    		mCurrentCadence = 0;
    	}    	
    	
    	if (info.elapsedDistance != null) {
    		mElapsedDistance = info.elapsedDistance;
			lapElapsedDistance 	= mElapsedDistance - lastLapDistMarker;
    	} else {
    		mElapsedDistance = 0.0;
    		lapElapsedDistance 	= 0;
    	}
    	
    	if (lapTimerTime > 0 && lapElapsedDistance > 0) {
    		lapSpeed = lapElapsedDistance / lapTimerTime;
    	} else {
    		lapSpeed = 0.0;
    	}

    	if (info.averageSpeed != null) {
    		mAverageSpeed = info.averageSpeed;
    	} else {
    		mAverageSpeed = 0.0;
    	}
    	
    	if (stoppedSeconds == 0) {
    		movingSpeed = mAverageSpeed;
    	} else {
	    	if (mTimerTime > 0 && stoppedSeconds < mTimerTime) {
	    		movingSpeed = mElapsedDistance / (mTimerTime - stoppedSeconds);
	    	} else {
	    		movingSpeed = mAverageSpeed;
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
    	
    	if (targetPaceMetric == 0) {
			targetSpeed = mAverageSpeed;
		} else if (targetPaceMetric == 1) {
			targetSpeed = movingSpeed;
		} else if (targetPaceMetric == 2) {
			targetSpeed = lapSpeed;
		} else if (targetPaceMetric == 3) {
			targetSpeed = lapMovingSpeed;
		} else if (targetPaceMetric == 4) {
			targetSpeed = lastLapSpeed;
		} else if (targetPaceMetric == 5) {
			targetSpeed = lastLapMovingSpeed;
		}
					
		if (targetSpeed > 0.0 && mCurrentSpeed > 1.8) {	//! Only use the pace colour indicator when running (1.8 m/s = 9:15 min/km, ~15:00 min/mi)
			paceDeviation = (mCurrentSpeed / targetSpeed);
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
		System.println("Timer: " + mTimerTime);
		System.println("Elapsed time: " + mElapsedTime);
		System.println("Stopped seconds: " + stoppedSeconds);
		System.println("Distance: " + mElapsedDistance);
		System.println("Current speed: " + mCurrentSpeed);
		System.println("Average speed: " + mAverageSpeed);
		if (paceDeviation != null) {
			System.println("Pace deviation: " + (paceDeviation * 100).format("%d") + "%");
		} else {
			System.println("Pace deviation: N/A");
		}
		System.println("Average moving (running) speed: " + movingSpeed);
		System.println("Current heart rate: " + mCurrentHeartRate);
		System.println("Current heart rate zone: " + hrZone);
		System.println("Current cadence: " + mCurrentCadence);
		System.println("Laps: " + laps);
		System.println("Lap timer: " + lapTimerTime);
		System.println("Lap stopped seconds: " + lapStoppedSeconds);
		System.println("Lap distance: " + lapElapsedDistance);
		System.println("Lap speed: " + lapSpeed);
		System.println("Lap moving (running) speed: " + lapMovingSpeed);
		System.println("Last lap timer: " + lastLapTimerTime);
		System.println("Last lap distance: " + lastLapElapsedDistance);
		System.println("Last lap speed: " + lastLapSpeed);
		System.println("Last lap moving (running) speed: " + lastLapMovingSpeed);
		System.println("==================================================");
/**/
		mCurrentSpeed = 3.2;
		mAverageSpeed = 3.0;
		movingSpeed = 2.8;
    }

    //! Store last lap quantities and set lap markers
    function onTimerLap() {
    	lastLapTimerTime		= lapTimerTime;
    	lastLapElapsedDistance	= lapElapsedDistance;
    	lastLapSpeed			= lapSpeed;
    	lastLapMovingSpeed		= lapMovingSpeed;
    	laps++;
    	lastLapDistMarker 		= mElapsedDistance;
    	lastLapTimeMarker 		= mTimerTime;
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
    	var nudge = 0;
    	dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.clear();    	

    	//! Draw the HR field separator (if applicable) first, underneath the indicators
    	if (hrDisplay == 2) {
    		dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_WHITE);
        	dc.setPenWidth(2);
        	if ( (unitP == 1609.344 && mCurrentSpeed < 2.687) || (unitP == 1000.0 && mCurrentSpeed < 1.669) ) {
				dc.drawLine(0, 90, 55, 90);
			} else {
        		dc.drawLine(0, 90, 60, 90);
        	}
    	}

    	//!
    	//! Draw colour indicators first	
		//!	
		dc.setPenWidth(8);

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
		//dc.drawArc(111, 89, 106, dc.ARC_CLOCKWISE, 200, 158);
		//dc.drawArc(62, 105, 72, dc.ARC_CLOCKWISE, 205, 130);
		dc.drawArc(167, 89, 165, dc.ARC_CLOCKWISE, 192, 158);		
		dc.fillRectangle(0, 56, 69, 18);
		dc.fillRectangle(0, 56, 20, 26);	

		//! Set cadence zone indicator colour (fixed thresholds and colours to match Garmin, with the addition of grey for walking/stopped)
		if (mCurrentCadence > 183) {
			dc.setColor(Graphics.COLOR_PURPLE, Graphics.COLOR_TRANSPARENT);
		} else if (mCurrentCadence >= 174) {
			dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
		} else if (mCurrentCadence >= 164) {
			dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
		} else if (mCurrentCadence >= 153) {
			dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
		} else if (mCurrentCadence >= 120) {
			dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
		}  else {
			dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
		}
		//dc.drawArc(103, 89, 106, dc.ARC_CLOCKWISE, 20, 340);
		//dc.drawArc(142, 100, 80, dc.ARC_CLOCKWISE, 50, 335);
		dc.drawArc(47, 89, 165, dc.ARC_CLOCKWISE, 22, 348);
		dc.fillRectangle(144, 56, 71, 18);
		dc.fillRectangle(195, 56, 20, 26);

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
		if ( (unitP == 1609.344 && mCurrentSpeed < 2.687) || (unitP == 1000.0 && mCurrentSpeed < 1.669) ) {
			dc.fillRectangle(64, 56, 85, 18);
		} else {
			dc.fillRectangle(69, 56, 75, 18);		
		}		

		//! Chop tops and bottoms off arcs
		dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
		dc.fillRectangle(0, 30, 215, 26);
		dc.fillRectangle(0, 121, 215, 8);
		dc.fillCircle(16, 84, 10);
		dc.fillCircle(198, 84, 10);

    	//! Draw separator lines
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_WHITE);
        dc.setPenWidth(2);
        //! Horizontal thirds
		dc.drawLine(0, 56, 215, 56);
		dc.drawLine(0, 121, 215, 121);
		//! Top vertical divider adjustment - timer on the left, distance on the right: shift the divider to the right slightly if displaying additional seconds field for the timer
		if (mTimerTime > timerDisplayLimit) {
			if (mTimerTime < 7200) {
				dc.drawLine(109, 0, 109, 56);
			} else {
				dc.drawLine(110, 0, 110, 56);
			}
		} else {
			//! Distance on the left, timer on the right, and/or when not showing additional seconds
			dc.drawLine(107, 0, 107, 56);
		}
		//! Centre vertical dividers
		if ( (unitP == 1609.344 && mCurrentSpeed < 2.687) || (unitP == 1000.0 && mCurrentSpeed < 1.669) ) {
			dc.drawLine(64, 56, 64, 121);
			dc.drawLine(149, 56, 149, 121);
		} else {
			dc.drawLine(69, 56, 69, 121);
			dc.drawLine(144, 56, 144, 121);			
		}
		
		
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
        if ((mElapsedDistance/unitD) < 100) {
			fDistance = (mElapsedDistance/unitD).format("%.2f");
		} else {
			fDistance = (mElapsedDistance/unitD).format("%.1f");
		}

		var fTimerHours 	= (mTimerTime / 3600).format("%d");
		var fTimerMins 		= (mTimerTime / 60 % 60).format("%02d");
		var fTimerSecs 		= (mTimerTime % 60).format("%02d");
		var fTimerMinsAbs 	= (mTimerTime / 60).format("%d");
        //! Top row: timer and distance - additional seconds on timer causes distance field to be compressed
    	if (mTimerTime > timerDisplayLimit) {  	
    		//! Format time as h:mm(ss)
			if (mTimerTime < 7200) {
				//! Less than 2 hours - shift to left slightly since '1' takes up less space than other numbers
				dc.drawText(21, 34, Graphics.FONT_NUMBER_MEDIUM, fTimerHours + ":" + fTimerMins, Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
				dc.drawText(84, 26, Graphics.FONT_NUMBER_MILD, fTimerSecs, Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
			} else {
				//! Over 2 hours
				dc.drawText(23, 34, Graphics.FONT_NUMBER_MEDIUM, fTimerHours + ":" + fTimerMins, Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
				dc.drawText(85, 26, Graphics.FONT_NUMBER_MILD, fTimerSecs, Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
			}
			dc.drawText(152, 34, Graphics.FONT_NUMBER_MEDIUM, fDistance, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(117, 8, Graphics.FONT_XTINY,  "Distance", Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
		} else {
			//! Format time as m:ss
			dc.drawText(64, 34, Graphics.FONT_NUMBER_MEDIUM, fTimerMinsAbs + ":" + fTimerSecs, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(151, 34, Graphics.FONT_NUMBER_MEDIUM, fDistance, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(117, 8, Graphics.FONT_XTINY,  "Distance", Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
		}	
		dc.drawText(50, 8, Graphics.FONT_XTINY,  "Timer", Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);	

		if (mCurrentSpeed < 0.447164) {
			dc.drawLine(59, 116, 80, 116);
			dc.drawLine(81, 116, 102, 116);
			dc.drawLine(110, 116, 131, 116);
			dc.drawLine(132, 116, 153, 116);
			dc.drawText(106, 98, Graphics.FONT_NUMBER_MEDIUM, ":", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		} else {
			if ( (unitP == 1609.344 && mCurrentSpeed < 1.342) || (unitP == 1000.0 && mCurrentSpeed < 0.834) ) {
				dc.drawText(106, 98, Graphics.FONT_NUMBER_MEDIUM, fmtPace(unitP/(Math.round((unitP/mCurrentSpeed) / 5) * 5)), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			} else if ( (unitP == 1609.344 && mCurrentSpeed < 2.687) || (unitP == 1000.0 && mCurrentSpeed < 1.669) ) {
				dc.drawText(105, 98, Graphics.FONT_NUMBER_MEDIUM, fmtPace(unitP/(Math.round((unitP/mCurrentSpeed) / 5) * 5)), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			} else {
				dc.drawText(107, 98, Graphics.FONT_NUMBER_MEDIUM, fmtPace(unitP/(Math.round((unitP/mCurrentSpeed) / 5) * 5)), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			}
		}    	
		dc.drawText(107, 64, Graphics.FONT_XTINY,  "Pace", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		
		//! Centre left: heart rate
		var hrBpm = (mCurrentHeartRate > 0) ? mCurrentHeartRate : "--";
		nudge = (mCurrentHeartRate < 200) ? 0 : 2;
		if (hrDisplay == 2) {			
			dc.drawText(32 + nudge, 72, Graphics.FONT_NUMBER_MILD, hrBpm, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(34, 104, Graphics.FONT_NUMBER_MILD, hrZone.format("%.1f"), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(6, 81, Graphics.FONT_XTINY, "H", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(6, 94, Graphics.FONT_XTINY, "R", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		} else if (hrDisplay == 1) {
			dc.drawText(38, 98, Graphics.FONT_NUMBER_MEDIUM, hrZone.format("%.1f"), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(35, 64, Graphics.FONT_XTINY, "HR Zone", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		} else { //if (hrDisplay == 0) {
			dc.drawText(36 + nudge, 98, Graphics.FONT_NUMBER_MEDIUM, hrBpm, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(35, 64, Graphics.FONT_XTINY, "HR", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}
		
		//! Centre right: cadence
		nudge = (mCurrentCadence < 200) ? (mCurrentCadence < 100) ? 4 : 0 : 2;
		dc.drawText(173 + nudge, 98, Graphics.FONT_NUMBER_MEDIUM, mCurrentCadence, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER); 
		dc.drawText(179, 64, Graphics.FONT_XTINY,  "Cadence", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER); 

		//! Bottom left
		var fPace = 0;
		var lPace = "";
		if (bottomLeftData == 0) {
			fPace = mAverageSpeed;
			lPace = "Avg. Pace";
		} else if (bottomLeftData == 1) {
			fPace = movingSpeed;
			lPace = "Run. Pace";
		} else if (bottomLeftData == 2) {
			fPace = lapSpeed;
			lPace = "Lap Pace";
		} else if (bottomLeftData == 3) {
			fPace = lapMovingSpeed;
			lPace = "Lap R Pace";
		} else if (bottomLeftData == 4) {
			fPace = lastLapSpeed;
			lPace = "L-1 Pace";
		} else if (bottomLeftData == 5) {
			fPace = lastLapMovingSpeed;
			lPace = "L-1 R Pace";
		}
		if (fPace < 0.447164) {
			dc.drawLine(26, 156, 43, 156);
			dc.drawLine(44, 156, 61, 156);
			dc.drawLine(69, 156, 86, 156);
			dc.drawLine(87, 156, 104, 156);
			dc.drawText(65, 138, Graphics.FONT_NUMBER_MEDIUM, ":", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		} else {
			dc.drawText(60, 141, Graphics.FONT_NUMBER_MEDIUM, fmtPace(fPace), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}
		dc.drawText(72, 167, Graphics.FONT_XTINY, lPace, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			
		//! Bottom right
		fPace = 0;
		lPace = "";
		if (bottomRightData == 0) {
			fPace = mAverageSpeed;
			lPace = "Avg. Pace";
		} else if (bottomRightData == 1) {
			fPace = movingSpeed;
			lPace = "Run. Pace";
		} else if (bottomRightData == 2) {
			fPace = lapSpeed;
			lPace = "Lap Pace";
		} else if (bottomRightData == 3) {
			fPace = lapMovingSpeed;
			lPace = "Lap R Pace";
		} else if (bottomRightData == 4) {
			fPace = lastLapSpeed;
			lPace = "L-1 Pace";
		} else if (bottomRightData == 5) {
			fPace = lastLapMovingSpeed;
			lPace = "L-1 R Pace";
		}
		if (fPace < 0.447164) {
			dc.drawLine(111, 156, 128, 156);
			dc.drawLine(129, 156, 146, 156);
			dc.drawLine(154, 156, 171, 156);
			dc.drawLine(172, 156, 189, 156);
			dc.drawText(150, 138, Graphics.FONT_NUMBER_MEDIUM, ":", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		} else {
			dc.drawText(150, 141, Graphics.FONT_NUMBER_MEDIUM, fmtPace(fPace), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}
		dc.drawText(141, 167, Graphics.FONT_XTINY, lPace, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

    }
        
    
    function fmtPace(secs) {
        return ((unitP/secs).toLong() / 60).format("%0d") + ":" + ((unitP/secs).toLong() % 60).format("%02d");
    }

}
