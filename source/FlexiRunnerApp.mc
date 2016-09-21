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

	hidden var mTargetPaceMetric = 0;	//! Which average pace metric should be used as the reference for deviation of the current pace? (see above)

	hidden var mLaps = 1;
	hidden var mLastLapDistMarker = 0.0;
    hidden var mLastLapTimeMarker = 0;
    hidden var mLastLapStoppedTimeMarker = 0;

	hidden var mLastLapTimerTime = 0;
	hidden var mLastLapElapsedDistance = 0.0;
	hidden var mLastLapStoppedTime = 0;

    function initialize() {
        DataField.initialize();

 		mHrZones = UserProfile.getHeartRateZones(UserProfile.getCurrentSport());
 		var mApp = Application.getApp();
 		mHrDisplay 				= mApp.getProperty("pHR");
 		mTargetPaceMetric		= mApp.getProperty("pPace");
 		mBottomLeftMetric		= mApp.getProperty("pFL");
 		mBottomRightMetric		= mApp.getProperty("pFR");

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
		}
    }

    //! Store last lap quantities and set lap markers
    function onTimerLap() {
    	var info = Activity.getActivityInfo();
    	mLastLapTimerTime		= (info.timerTime - mLastLapTimeMarker) / 1000;
    	mLastLapElapsedDistance	= info.elapsedDistance - mLastLapDistMarker;
    	mLastLapStoppedTime		= mStoppedTime - mLastLapStoppedTimeMarker;
    	mLaps++;
    	mLastLapDistMarker 			= info.elapsedDistance;
    	mLastLapTimeMarker 			= info.timerTime;
    	mLastLapStoppedTimeMarker	= mStoppedTime;
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
    	var x;
    	var width;
    	if (info.currentSpeed == null || info.currentSpeed < ddSpdLimit) {	//! Set up variables for flexible centre field
			x = 64;
			width = 85;
		} else {
			x = 70;
			width = 75;
		}    	

    	//! Calculate lap distance, format total distance
    	var fElapsedDistance = "0.00";
    	var mLapElapsedDistance = 0.0;
    	 if (info.elapsedDistance != null) {
    	 	var dist = info.elapsedDistance / unitD;
    	 	if (dist > 100) {
    	 		fElapsedDistance = dist.format("%.1f");
    	 	} else {
    	 		fElapsedDistance = dist.format("%.2f");
    	 	}
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
    	var mLastLapMovingSpeed = 0.0;
    	var mLapStoppedTime = mStoppedTime - mLastLapStoppedTimeMarker;

    	if (mTimerTime > 0
    		&& mStoppedTime > 0
    		&& mStoppedTime < mTimerTime
    		&& info.elapsedDistance != null) {
    		mMovingSpeed = info.elapsedDistance / (mTimerTime - mStoppedTime);
		} else if (info.averageSpeed != null) {
			mMovingSpeed = info.averageSpeed;
		}

		if (mLapTimerTime > 0
    		&& mLapStoppedTime > 0
    		&& mLapStoppedTime < mLapTimerTime
    		&& mLapElapsedDistance != null) {
    		mLapMovingSpeed = mLapElapsedDistance / (mLapTimerTime - mLapStoppedTime);
		} else {
			mLapMovingSpeed = mLapSpeed;
		}

		if (mLastLapTimerTime > 0
    		&& mLastLapStoppedTime > 0
    		&& mLastLapStoppedTime < mLastLapTimerTime
    		&& mLastLapElapsedDistance != null) {
    		mLastLapMovingSpeed = mLastLapElapsedDistance / (mLastLapTimerTime - mLastLapStoppedTime);
		} else {
			mLastLapMovingSpeed = mLastLapSpeed;
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
		if (mHrZone >= 5.0) {
			mColour = Graphics.COLOR_RED;		//! Maximum
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
			dc.fillRectangle(0, 50, 30, 15);
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
							[75, 64],
							[0,  64]]);
		}

		//! Cadence zone indicator colour (fixed thresholds and colours to match Garmin, with the addition of grey for walking/stopped)
		mColour = Graphics.COLOR_LT_GRAY;
		if (info.currentCadence != null) {
			if (info.currentCadence > 183) {
				mColour = Graphics.COLOR_PURPLE;
			} else if (info.currentCadence >= 174) {
				mColour = Graphics.COLOR_BLUE;
			} else if (info.currentCadence >= 164) {
				mColour = Graphics.COLOR_GREEN;
			} else if (info.currentCadence >= 153) {
				mColour = Graphics.COLOR_ORANGE;
			} else if (info.currentCadence >= 120) {
				mColour = Graphics.COLOR_RED;
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
						[140, 64],
						[215, 64]]);

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

		if (mTargetSpeed > 0.0 && info.currentSpeed != null && info.currentSpeed > 1.8) {	//! Only use the pace colour indicator when running (1.8 m/s = 9:15 min/km, ~15:00 min/mi)
			var paceDeviation = (info.currentSpeed / mTargetSpeed);
			if (paceDeviation < 0.90) {	//! More than 10% slower
				mColour = Graphics.COLOR_RED;
			} else if (paceDeviation < 0.95) {	//! 5-10% slower
				mColour = Graphics.COLOR_ORANGE;
			} else if (paceDeviation <= 1.05) {	//! Between 5% slower and 5% faster
				mColour = Graphics.COLOR_GREEN;
			} else if (paceDeviation <= 1.10) {	//! 5-10% faster
				mColour = Graphics.COLOR_BLUE;
			} else {  //! More than 10% faster
				mColour = Graphics.COLOR_PURPLE;
			}
		} else {
			mColour = Graphics.COLOR_LT_GRAY;
		}
		dc.setColor(mColour, Graphics.COLOR_TRANSPARENT);
		dc.fillRectangle(x, 65, width, 16);

    	//! Draw separator lines
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);

        //! Horizontal thirds
		dc.drawLine(0, 64, 215, 64);
		dc.drawLine(0, 122, 215, 122);

		//! Top vertical divider
		dc.drawLine(107, 26, 107, 64);

		//! Top centre mini-field separator
		dc.drawRoundedRectangle(90, -10, 35, 36, 4);
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

		//! Centre vertical dividers
		dc.drawLine(x, 64, x, 122);
		dc.drawLine(x + width, 64, x + width, 122);

		//! Bottom vertical divider
		dc.drawLine(107, 122, 107, 180);

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
		dc.drawText(106, -4, Graphics.FONT_NUMBER_MILD, mLaps, Graphics.TEXT_JUSTIFY_CENTER);
		
		var fTimerSecs = (mTimerTime % 60).format("%02d");
		var fTimer;
        //! Top row: time and distance
    	if (mTimerTime > 3599) {
    		//! Format time as h:mm(ss)
    		fTimer = (mTimerTime / 3600).format("%d") + ":" + (mTimerTime / 60 % 60).format("%02d");
    		x = 48;
			dc.drawText(80, 35, Graphics.FONT_NUMBER_MILD, fTimerSecs, Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
		} else {
			//! Format time as m:ss
			fTimer = (mTimerTime / 60).format("%d") + ":" + fTimerSecs;
			x = 61;
		}
		dc.drawText(x, 42, Graphics.FONT_NUMBER_MEDIUM, fTimer, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

		dc.drawText(154, 42, Graphics.FONT_NUMBER_MEDIUM, fElapsedDistance, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		dc.drawText(157, 17, Graphics.FONT_XTINY,  "Distance", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		dc.drawText(62, 17, Graphics.FONT_XTINY,  "Timer", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

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
		dc.drawText(107, 71, Graphics.FONT_XTINY,  "Pace", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

		//! Centre left: heart rate
		if (mHrDisplay == 2) {
			dc.drawText(37, 77, Graphics.FONT_NUMBER_MILD, mCurrentHeartRate, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(38, 106, Graphics.FONT_NUMBER_MILD, mHrZone.format("%.1f"), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(6, 83, Graphics.FONT_XTINY, "H", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(6, 96, Graphics.FONT_XTINY, "R", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		} else {
			var fHr = mCurrentHeartRate;
			var lHr = "HR";
			if (mHrDisplay == 1) {
				fHr = mHrZone.format("%.1f");
				lHr = "HR Zone";
			}
			dc.drawText(35, 100, Graphics.FONT_NUMBER_MEDIUM, fHr, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
			dc.drawText(35, 71, Graphics.FONT_XTINY, lHr, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}

		//! Centre right: cadence
		dc.drawText(176, 100, Graphics.FONT_NUMBER_MEDIUM, (info.currentCadence != null) ? info.currentCadence : 0, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		dc.drawText(180, 71, Graphics.FONT_XTINY,  "Cadence", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

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
