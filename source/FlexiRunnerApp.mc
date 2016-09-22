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

	hidden var mHrZones;
	hidden var unitP = 1000.0;
	hidden var unitD = 1000.0;
	hidden var ddSpdLimit = 1.669;
	hidden var dd2SpdLimit = 0.834;

	hidden var mTimerDisplay = 0;
	//! 0 => Timer
	//! 1 => Moving (timer) time
	//! 2 => Elapsed time
	//! 3 => Lap time
	//! 4 => Last lap time
	//! 5 => Average lap time

	hidden var mDistDisplay = 0;
	//! 0 => Total distance
	//! 1 => Moving distance
	//! 2 => Lap distance
	//! 3 => Last lap distance
	//! 4 => Average lap time

	hidden var mHrDisplay = 0;
	//! 0 => Direct heart rate in bpm
	//! 1 => Heart rate decimal zone (e.g. 3.5)
	//! 2 => Both bpm and zone

	hidden var mBottomLeftMetric = 1;	//! Data to show in bottom left field
	hidden var mBottomRightMetric = 0;	//! Data to show in bottom right field
	//! Paces enum:
	//! 0 => (overall) average pace
	//! 1 => Moving (running) pace
	//! 2 => Lap pace
	//! 3 => Lap moving (running) pace
	//! 4 => Last lap pace
	//! 5 => Last lap moving (running) pace

	hidden var mTimerRunning = false;

	hidden var mStoppedTime = 0;
	hidden var mStoppedDistance = 0;
	hidden var mLastMovingDistMarker = 0;

	hidden var mTargetPaceMetric = 0;	//! Which average pace metric should be used as the reference for deviation of the current pace? (see above)

	hidden var mLaps = 1;
	hidden var mLastLapDistMarker = 0.0;
    hidden var mLastLapTimeMarker = 0;
    hidden var mLastLapStoppedTimeMarker = 0;
    hidden var mLastLapStoppedDistMarker = 0;

	hidden var mLastLapTimerTime = 0;
	hidden var mLastLapElapsedDistance = 0.0;
	hidden var mLastLapMovingSpeed = 0.0;

    function initialize() {
        DataField.initialize();

 		mHrZones = UserProfile.getHeartRateZones(UserProfile.getCurrentSport());
 		var mApp = Application.getApp();
 		mTimerDisplay			= mApp.getProperty("pTimerDisplay");
 		mDistDisplay			= mApp.getProperty("pDistDisplay");
 		mHrDisplay 				= mApp.getProperty("pHrDisplay");
 		mTargetPaceMetric		= mApp.getProperty("pTargetPace");
 		mBottomLeftMetric		= mApp.getProperty("pBottomLeftMetric");
 		mBottomRightMetric		= mApp.getProperty("pBottomRightMetric");

        if (System.getDeviceSettings().paceUnits == System.UNIT_STATUTE) {
        	unitP = 1609.344;
        	ddSpdLimit = 2.687;
        	dd2SpdLimit = 1.342;
        }

        if (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE) {
        	unitD = 1609.344;
        }

    }


    //! Calculations we need to do every second even when the data field is not visible
    function compute(info) {
    	if (mTimerRunning && info.currentSpeed != null && info.currentSpeed < 1.8) { //! Speed below which the moving time timer is paused (1.8 m/s = 9:15 min/km, ~15:00 min/mi)
			//! Simple non-moving time calculation - relies on compute() being called every second
			mStoppedTime++;
			if (info.elapsedDistance != null) {
				mStoppedDistance += info.elapsedDistance - mLastMovingDistMarker;
			}
		}
		if (info.elapsedDistance != null) {
			mLastMovingDistMarker = info.elapsedDistance;
		}
    }

    //! Store last lap quantities and set lap markers
    function onTimerLap() {
    	var info = Activity.getActivityInfo();
    	mLastLapTimerTime			= (info.timerTime - mLastLapTimeMarker) / 1000;
    	mLastLapElapsedDistance		= (info.elapsedDistance != null) ? info.elapsedDistance - mLastLapDistMarker : 0;
    	var mLastLapStoppedTime		= mStoppedTime - mLastLapStoppedTimeMarker;
    	var mLastLapStoppedDistance	= mStoppedDistance - mLastLapStoppedDistMarker;
    	if (mLastLapTimerTime > 0
    		&& mLastLapStoppedTime > 0
    		&& mLastLapStoppedTime < mLastLapTimerTime
    		&& mLastLapElapsedDistance != null) {
    		mLastLapMovingSpeed = (mLastLapElapsedDistance - mLastLapStoppedDistance) / (mLastLapTimerTime - mLastLapStoppedTime);
		} else {
			mLastLapMovingSpeed = (mLastLapTimerTime > 0) ? mLastLapElapsedDistance / mLastLapTimerTime : 0.0;
		}
    	mLaps++;
    	mLastLapDistMarker 			= info.elapsedDistance;
    	mLastLapTimeMarker 			= info.timerTime;
    	mLastLapStoppedTimeMarker	= mStoppedTime;
    	mLastLapStoppedDistMarker	= mStoppedDistance;
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


    //! Do necessary calculations and draw fields.
    //! This will be called once a second when the data field is visible.
    function onUpdate(dc) {
    	var info = Activity.getActivityInfo();

    	var mColour;
    	var labelColour;
    	var x;
    	var width;
    	if (info.currentSpeed == null || info.currentSpeed < ddSpdLimit) {	//! Set up variables for flexible centre field
			x = 64;
			width = 85;
		} else {
			x = 70;
			width = 75;
		}    	

    	//! Calculate lap distance
    	var mLapElapsedDistance = 0.0;
    	if (info.elapsedDistance != null) {
			mLapElapsedDistance = info.elapsedDistance - mLastLapDistMarker;
    	}

    	//! Calculate lap time and convert timers from milliseconds to seconds
    	var mTimerTime = 0;
    	var mLapTimerTime = 0;

    	if (info.timerTime != null) {
			mTimerTime = info.timerTime / 1000;
    		mLapTimerTime = (info.timerTime - mLastLapTimeMarker) / 1000;
    	}

    	//! Calculate lap speeds
    	var mLapSpeed = 0.0;
    	var mLastLapSpeed = 0.0;    	
    	if (mLapTimerTime > 0 && mLapElapsedDistance > 0) {
    		mLapSpeed = mLapElapsedDistance / mLapTimerTime;
    	}
    	if (mLastLapTimerTime > 0 && mLastLapElapsedDistance > 0) {
    		mLastLapSpeed = mLastLapElapsedDistance / mLastLapTimerTime;
    	}

    	//! Calculate moving speeds
    	var mMovingSpeed = 0.0;
    	var mLapMovingSpeed = 0.0;
    	var mLapStoppedTime = mStoppedTime - mLastLapStoppedTimeMarker;
    	var mLapStoppedDistance = mStoppedDistance - mLastLapStoppedDistMarker;

    	if (mTimerTime > 0
    		&& mStoppedTime > 0
    		&& mStoppedTime < mTimerTime
    		&& info.elapsedDistance != null) {
    		mMovingSpeed = (info.elapsedDistance - mStoppedDistance) / (mTimerTime - mStoppedTime);
		} else if (info.averageSpeed != null) {
			mMovingSpeed = info.averageSpeed;
		}

		if (mLapTimerTime > 0
    		&& mLapStoppedTime > 0
    		&& mLapStoppedTime < mLapTimerTime
    		&& mLapElapsedDistance != null) {
    		mLapMovingSpeed = (mLapElapsedDistance - mLapStoppedDistance) / (mLapTimerTime - mLapStoppedTime);
		} else {
			mLapMovingSpeed = mLapSpeed;
		}

    	//! Calculate HR zone
    	var mHrZone = 0.0;
    	var mCurrentHeartRate = "--";
    	if (info.currentHeartRate != null) {
    		mCurrentHeartRate = info.currentHeartRate;
			if (mHrZones != null) {
		    	if (info.currentHeartRate < mHrZones[0]) {
					mHrZone = info.currentHeartRate / mHrZones[0].toFloat();
				} else if (info.currentHeartRate < mHrZones[1]) {
					mHrZone = 1 + (info.currentHeartRate - mHrZones[0]) / (mHrZones[1] - mHrZones[0]).toFloat();
				} else if (info.currentHeartRate < mHrZones[2]) {
					mHrZone = 2 + (info.currentHeartRate - mHrZones[1]) / (mHrZones[2] - mHrZones[1]).toFloat();
				} else if (info.currentHeartRate < mHrZones[3]) {
					mHrZone = 3 + (info.currentHeartRate - mHrZones[2]) / (mHrZones[3] - mHrZones[2]).toFloat();
				} else if (info.currentHeartRate < mHrZones[4]) {
					mHrZone = 4 + (info.currentHeartRate - mHrZones[3]) / (mHrZones[4] - mHrZones[3]).toFloat();
				} else {
					mHrZone = 5 + (info.currentHeartRate - mHrZones[4]) / (mHrZones[5] - mHrZones[4]).toFloat();
				}
			}
    	}

     	//!
    	//! Draw colour indicators
		//!

		//! HR zone indicator
		mColour = Graphics.COLOR_LT_GRAY;
		labelColour = Graphics.COLOR_BLACK;
		if (mHrZone >= 5.0) {
			mColour = Graphics.COLOR_RED;		//! Maximum
			labelColour = Graphics.COLOR_WHITE;
		} else if (mHrZone >= 4.0) {
			mColour = Graphics.COLOR_ORANGE;	//! Threshold
		} else if (mHrZone >= 3.0) {
			mColour = Graphics.COLOR_GREEN;		//! Aerobic
		} else if (mHrZone >= 2.0) {
			mColour = Graphics.COLOR_BLUE;		//! Easy
		} //! Else Warm-up and no zone inherit default light grey here
		dc.setColor(mColour, Graphics.COLOR_TRANSPARENT);
		if (mHrDisplay == 2) {
			dc.setPenWidth(18);
			dc.drawArc(111, 93, 106, dc.ARC_CLOCKWISE, 200, 158);
			dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
			dc.fillRectangle(0, 49, 30, 15);
			dc.fillRectangle(0, 122, 30, 15);
		} else {
			dc.fillPolygon([[0,  122],
							[9,  122],
							[7,  116],
							[6,  111],
							[5,  107],
							[5,  95],
							[6,  91],
							[7,  88],
							[8,  87],
							[9,  85],
							[10, 84],
							[13, 82],
							[16, 81],
							[75, 81],
							[75, 63],
							[0,  63]]);
		}
		dc.setColor(labelColour, Graphics.COLOR_TRANSPARENT);
		if (mHrDisplay == 2) {
			dc.drawText(6, 83, Graphics.FONT_XTINY, "H", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(6, 96, Graphics.FONT_XTINY, "R", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		} else {
			var lHr = "HR";
			if (mHrDisplay == 1) {
				lHr = "HR Zone";
			}
			dc.drawText(34, 71, Graphics.FONT_XTINY, lHr, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}

		//! Cadence zone indicator colour (fixed thresholds and colours to match Garmin, with the addition of grey for walking/stopped)
		mColour = Graphics.COLOR_LT_GRAY;
		labelColour = Graphics.COLOR_BLACK;
		if (info.currentCadence != null) {
			if (info.currentCadence > 183) {
				mColour = Graphics.COLOR_PURPLE;
				labelColour = Graphics.COLOR_WHITE;
			} else if (info.currentCadence >= 174) {
				mColour = Graphics.COLOR_BLUE;
			} else if (info.currentCadence >= 164) {
				mColour = Graphics.COLOR_GREEN;
			} else if (info.currentCadence >= 153) {
				mColour = Graphics.COLOR_ORANGE;
			} else if (info.currentCadence >= 120) {
				mColour = Graphics.COLOR_RED;
				labelColour = Graphics.COLOR_WHITE;
			}
		}
		dc.setColor(mColour, Graphics.COLOR_TRANSPARENT);
		dc.fillPolygon([[215, 122],
						[205, 122],
						[207, 116],
						[208, 111],
						[209, 107],
						[209, 95],
						[208, 91],
						[207, 88],
						[206, 87],
						[205, 85],
						[204, 84],
						[201, 82],
						[198, 81],
						[140, 81],
						[140, 63],
						[215, 63]]);
		dc.setColor(labelColour, Graphics.COLOR_TRANSPARENT);
		dc.drawText(180, 71, Graphics.FONT_XTINY,  "Cadence", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

		//! Current pace vs (moving) average pace colour indicator
		var mTargetSpeed = 0.0;
		if (mTargetPaceMetric == 0 && info.averageSpeed != null) {
			mTargetSpeed = info.averageSpeed;
		} else if (mTargetPaceMetric == 1) {
			mTargetSpeed = mMovingSpeed;
		} else if (mTargetPaceMetric == 2) {
			mTargetSpeed = mLapSpeed;
		} else if (mTargetPaceMetric == 3) {
			mTargetSpeed = mLapMovingSpeed;
		} else if (mTargetPaceMetric == 4) {
			mTargetSpeed = mLastLapSpeed;
		} else if (mTargetPaceMetric == 5) {
			mTargetSpeed = mLastLapMovingSpeed;
		}

		mColour = Graphics.COLOR_LT_GRAY;
		labelColour = Graphics.COLOR_BLACK;
		if (mTargetSpeed > 0.0 && info.currentSpeed != null && info.currentSpeed > 1.8) {	//! Only use the pace colour indicator when running (1.8 m/s = 9:15 min/km, ~15:00 min/mi)
			var paceDeviation = (info.currentSpeed / mTargetSpeed);
			if (paceDeviation < 0.90) {	//! More than 10% slower
				mColour = Graphics.COLOR_RED;
				labelColour = Graphics.COLOR_WHITE;
			} else if (paceDeviation < 0.95) {	//! 5-10% slower
				mColour = Graphics.COLOR_ORANGE;
			} else if (paceDeviation <= 1.05) {	//! Between 5% slower and 5% faster
				mColour = Graphics.COLOR_GREEN;
			} else if (paceDeviation <= 1.10) {	//! 5-10% faster
				mColour = Graphics.COLOR_BLUE;
			} else {  //! More than 10% faster
				mColour = Graphics.COLOR_PURPLE;
				labelColour = Graphics.COLOR_WHITE;
			}
		}
		dc.setColor(mColour, Graphics.COLOR_TRANSPARENT);
		dc.fillRectangle(x, 64, width, 17);
		dc.setColor(labelColour, Graphics.COLOR_TRANSPARENT);
		dc.drawText(107, 71, Graphics.FONT_XTINY,  "Pace", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

    	//! Draw separator lines
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);

        //! Horizontal thirds
		dc.drawLine(0, 63, 215, 63);
		dc.drawLine(0, 122, 215, 122);

		//! Top vertical divider
		dc.drawLine(107, 26, 107, 63);

		//! Centre vertical dividers
		dc.drawLine(x, 63, x, 122);
		dc.drawLine(x + width, 63, x + width, 122);

		//! Bottom vertical divider
		dc.drawLine(107, 122, 107, 180);

		//! Top centre mini-field separator
		if (mLaps > 9) {
			x = 92;
			width = 32;
		} else {
			x = 96;
			width = 25;
		}
		dc.drawRoundedRectangle(x, -10, width, 36, 4);
		/*
		dc.fillPolygon([[74,  -10],
						[88,   15],
						[90,   16],
						[92,   17],
						[123,  17],
						[125,  16],
						[127,  15],
						[141, -10]]);
		/**/
		
		//! HR field separator (if applicable)
    	if (mHrDisplay == 2) {
    		dc.drawLine(14, 93, x, 93);
    	}

		//! Fill in top centre mini-field polygon
		/*
		dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
		dc.fillPolygon([[76,  -12],
						[90,   13],
						[92,   14],
						[94,   15],
						[121,  15],
						[123,  14],
						[125,  13],
						[139, -12]]);
		/**/

        //!
        //! Draw fields
        //! ===========
        //!

        //! Set text colour
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);

		//dc.drawText(107, -3, Graphics.FONT_XTINY, System.getClockTime().hour.format("%d") + ":" + System.getClockTime().min.format("%02d"), Graphics.TEXT_JUSTIFY_CENTER);
		dc.drawText(107, -4, Graphics.FONT_NUMBER_MILD, mLaps, Graphics.TEXT_JUSTIFY_CENTER);
		
		//! Top row: time
		var mTime = mTimerTime;
		var lTime = "Timer";
		/*
		if (mTimerDisplay == 0) {
			mTime = mTimerTime;
			lTime = "Timer";
		} else
		/**/
		if (mTimerDisplay == 1) {
			mTime = mTimerTime - mStoppedTime;
			lTime = "Running";
		} else if (mTimerDisplay == 2) {
			mTime = (info.elapsedTime != null) ? info.elapsedTime / 1000 : 0;
			lTime = "Elapsed";
		} else if (mTimerDisplay == 3) {
			mTime = mLapTimerTime;
			lTime = "Lap Time";
		} else if (mTimerDisplay == 4) {
			mTime = mLastLapTimerTime;
			lTime = "Last Lap";
		} else if (mTimerDisplay == 5) {
			mTime = mTimerTime / mLaps;
			lTime = "Avg. Lap";
		}

		var fTimerSecs = (mTime % 60).format("%02d");
		var fTimer;        
    	if (mTime > 3599 && mTime < 36000) {
    		//! Format time as h:mm(ss) if more than an hour (but less than 10 hours)
    		fTimer = (mTime / 3600).format("%d") + ":" + (mTime / 60 % 60).format("%02d");
    		x = 48;
			dc.drawText(80, 35, Graphics.FONT_NUMBER_MILD, fTimerSecs, Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
		} else {
			//! Format time as m:ss
			fTimer = (mTime / 60).format("%d") + ":" + fTimerSecs;
			x = 61;
		}
		dc.drawText(x, 41, Graphics.FONT_NUMBER_MEDIUM, fTimer, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		dc.drawText(62, 15, Graphics.FONT_XTINY,  lTime, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

		//! Top row: distance
		var mDistance = (info.elapsedDistance != null) ? info.elapsedDistance / unitD : 0;
		var lDistance = "Distance";
		/*
		if (mDistDisplay == 0) {
			mDist = (info.elapsedDistance != null) ? info.elapsedDistance / unitD : 0;
			lDist = "Distance";
		} else
		/**/
		if (mDistDisplay == 1) {
			mDistance = (info.elapsedDistance != null) ? (info.elapsedDistance - mStoppedDistance) / unitD : 0;
			lDistance = "Run. Dist.";
		} else if (mDistDisplay == 2) {
			mDistance = mLapElapsedDistance / unitD;
			lDistance = "Lap Dist.";
		} else if (mDistDisplay == 3) {
			mDistance = mLastLapElapsedDistance / unitD;
			lDistance = "L-1 Dist.";
		} else if (mDistDisplay == 4) {
			mDistance = (info.elapsedDistance != null) ? (info.elapsedDistance / mLaps) / unitD : 0;
			lDistance = "Avg. Lap";
		}

		var fDistance;
	 	if (mDistance > 100) {
	 		fDistance = mDistance.format("%.1f");
	 	} else {
	 		fDistance = mDistance.format("%.2f");
	 	}
		dc.drawText(154, 41, Graphics.FONT_NUMBER_MEDIUM, fDistance, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		dc.drawText(156, 15, Graphics.FONT_XTINY,  lDistance, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		

		if (info.currentSpeed == null || info.currentSpeed < 0.447164) {
			drawSpeedUnderlines(dc, 107, 99);
		} else {
			if (info.currentSpeed < dd2SpdLimit) {
				x = 107;
			} else if (info.currentSpeed < ddSpdLimit) {
				x = 105;
			} else {
				x = 108;
			}
			dc.drawText(x, 100, Graphics.FONT_NUMBER_MEDIUM, fmtPace(unitP/(Math.round((unitP/info.currentSpeed) / 5) * 5)), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}

		//! Centre left: heart rate
		if (mHrDisplay == 2) {
			dc.drawText(37, 77, Graphics.FONT_NUMBER_MILD, mCurrentHeartRate, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(38, 106, Graphics.FONT_NUMBER_MILD, mHrZone.format("%.1f"), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		} else {
			var fHr = mCurrentHeartRate;
			if (mHrDisplay == 1) {
				fHr = mHrZone.format("%.1f");
			}
			dc.drawText(35, 100, Graphics.FONT_NUMBER_MEDIUM, fHr, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}

		//! Centre right: cadence
		dc.drawText(176, 100, Graphics.FONT_NUMBER_MEDIUM, (info.currentCadence != null) ? info.currentCadence : 0, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

		//! Bottom left
		var fPace = 0.0;
		var lPace = "Avg. Pace";
		if (mBottomLeftMetric == 0 && info.averageSpeed != null) {
			fPace = info.averageSpeed;
			//lPace = "Avg. Pace";
		} else if (mBottomLeftMetric == 1) {
			fPace = mMovingSpeed;
			lPace = "Run. Pace";
		} else if (mBottomLeftMetric == 2) {
			fPace = mLapSpeed;
			lPace = "Lap Pace";
		} else if (mBottomLeftMetric == 3) {
			fPace = mLapMovingSpeed;
			lPace = "Lap R Pace";
		} else if (mBottomLeftMetric == 4) {
			fPace = mLastLapSpeed;
			lPace = "L-1 Pace";
		} else if (mBottomLeftMetric == 5) {
			fPace = mLastLapMovingSpeed;
			lPace = "L-1 R Pace";
		}
		if (fPace < 0.447164) {
			drawSpeedUnderlines(dc, 65, 139);
		} else {
			dc.drawText(63, 142, Graphics.FONT_NUMBER_MEDIUM, fmtPace(fPace), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}
		dc.drawText(72, 167, Graphics.FONT_XTINY, lPace, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

		//! Bottom right
		fPace = 0.0;
		lPace = "Avg. Pace";
		if (mBottomRightMetric == 0 && info.averageSpeed != null) {
			fPace = info.averageSpeed;
			//lPace = "Avg. Pace";
		} else if (mBottomRightMetric == 1) {
			fPace = mMovingSpeed;
			lPace = "Run. Pace";
		} else if (mBottomRightMetric == 2) {
			fPace = mLapSpeed;
			lPace = "Lap Pace";
		} else if (mBottomRightMetric == 3) {
			fPace = mLapMovingSpeed;
			lPace = "Lap R Pace";
		} else if (mBottomRightMetric == 4) {
			fPace = mLastLapSpeed;
			lPace = "L-1 Pace";
		} else if (mBottomRightMetric == 5) {
			fPace = mLastLapMovingSpeed;
			lPace = "L-1 R Pace";
		}
		if (fPace < 0.447164) {
			drawSpeedUnderlines(dc, 150, 139);
		} else {
			dc.drawText(150, 142, Graphics.FONT_NUMBER_MEDIUM, fmtPace(fPace), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}
		dc.drawText(141, 167, Graphics.FONT_XTINY, lPace, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

    }


    function fmtPace(secs) {
    	var s = (unitP/secs).toLong();
        return (s / 60).format("%0d") + ":" + (s % 60).format("%02d");
    }


    function drawSpeedUnderlines(dc, x, y) {
    	var y2 = y + 18;
    	dc.drawLine(x - 39, y2, x - 22, y2);
		dc.drawLine(x - 21, y2, x - 4,  y2);
		dc.drawLine(x + 4,  y2, x + 21, y2);
		dc.drawLine(x + 22, y2, x + 39, y2);
		dc.drawText(x, y, Graphics.FONT_NUMBER_MEDIUM, ":", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
    }

}
