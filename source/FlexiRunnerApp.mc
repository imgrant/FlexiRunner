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

	hidden var uHrZones;
	hidden var unitP = 1000.0;
	hidden var unitD = 1000.0;

	hidden var uTimerDisplay = 0;
	//! 0 => Timer
	//! 1 => Moving (timer) time
	//! 2 => Elapsed time
	//! 3 => Lap time
	//! 4 => Last lap time
	//! 5 => Average lap time

	hidden var uDistDisplay = 0;
	//! 0 => Total distance
	//! 1 => Moving distance
	//! 2 => Lap distance
	//! 3 => Last lap distance
	//! 4 => Average lap time

	hidden var uHrDisplay = false;
	//! false => Direct heart rate in bpm
	//! true  => Heart rate decimal zone (e.g. 3.5)

	hidden var uCentreRightMetric = false;
	//! false => Current cadence
	//! true  => Running economy (recent average over last N seconds)

	hidden var uBottomLeftMetric  = 1;	//! Data to show in bottom left field
	hidden var uBottomRightMetric = 0;	//! Data to show in bottom right field
	//! Paces enum:
	//! 0 => (overall) average pace
	//! 1 => Moving (running) pace
	//! 2 => Lap pace
	//! 3 => Lap moving (running) pace
	//! 4 => Last lap pace
	//! 5 => Last lap moving (running) pace

	hidden var mTimerRunning = false;

	hidden var mStoppedTime 		= 0;
	hidden var mStoppedDistance 	= 0;
	hidden var mPrevElapsedDistance = 0;

	hidden var uTargetPaceMetric = 0;	//! Which average pace metric should be used as the reference for deviation of the current pace? (see above)

	hidden var mLaps 					 = 1;
	hidden var mLastLapDistMarker 		 = 0.0;
    hidden var mLastLapTimeMarker 		 = 0;
    hidden var mLastLapStoppedTimeMarker = 0;
    hidden var mLastLapStoppedDistMarker = 0;
    hidden var mLapHeartRateAccumulator  = 0;
    //hidden var mLapEconomy 			 = 0.0;

	hidden var mLastLapTimerTime 		= 0;
	hidden var mLastLapElapsedDistance 	= 0.0;
	hidden var mLastLapMovingSpeed 		= 0.0;
	//hidden var mLastLapHeartRate 		= 0;
	//hidden var mLastLapEconomy 		= 0.0;

	hidden var uRestingHeartRate 	= 60;
	hidden var mLastNDistanceMarker = 0.0;
	hidden var mLastNAvgHeartRate 	= 0.0;
	hidden var mLastNEconomy 		= 0.0;
	
	hidden var mTicker 		= 0;
	hidden var mLapTicker	= 0;

	hidden var mEconomyField 		= null;
	hidden var mAverageEconomyField = null;
	hidden var mLapEconomyField 	= null;

    function initialize() {
        DataField.initialize();

        var mProfile 		= UserProfile.getProfile();
 		uHrZones 			= UserProfile.getHeartRateZones(UserProfile.getCurrentSport());
 		uRestingHeartRate 	= mProfile.restingHeartRate;

 		var mApp = Application.getApp();
 		uTimerDisplay			= mApp.getProperty("pTimerDisplay");
 		uDistDisplay			= mApp.getProperty("pDistDisplay");
 		uHrDisplay 				= mApp.getProperty("pHrDisplay");
 		uTargetPaceMetric		= mApp.getProperty("pTargetPace");
 		uCentreRightMetric		= mApp.getProperty("pCentreRightMetric");
 		uBottomLeftMetric		= mApp.getProperty("pBottomLeftMetric");
 		uBottomRightMetric		= mApp.getProperty("pBottomRightMetric");

        if (System.getDeviceSettings().paceUnits == System.UNIT_STATUTE) {
        	unitP 		= 1609.344;
        }

        if (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE) {
        	unitD = 1609.344;
        }

        mEconomyField 		 = createField("running_economy", 0, FitContributor.DATA_TYPE_UINT16, { :mesgType=>FitContributor.MESG_TYPE_RECORD });
        mAverageEconomyField = createField("average_economy", 1, FitContributor.DATA_TYPE_UINT16, { :mesgType=>FitContributor.MESG_TYPE_SESSION });
        mLapEconomyField 	 = createField("lap_economy", 	  2, FitContributor.DATA_TYPE_UINT16, { :mesgType=>FitContributor.MESG_TYPE_LAP });
        
        mEconomyField.setData(0);
        mAverageEconomyField.setData(0);
        mLapEconomyField.setData(0);
    }


    //! Calculations we need to do every second even when the data field is not visible
    function compute(info) { 	
    	if (mTimerRunning) {  //! We only do calculations if the timer is running
    		mTicker++;
	        mLapTicker++;

    		var mElapsedDistance 		= (info.elapsedDistance != null) ? info.elapsedDistance : 0.0;
	    	var mDistanceIncrement 		= mElapsedDistance - mPrevElapsedDistance;
	    	var mLapElapsedDistance 	= mElapsedDistance - mLastLapDistMarker;
	    	var mLastNElapsedDistance 	= mElapsedDistance;
	    	if (mTicker > 30) {
	    		mLastNElapsedDistance = mElapsedDistance - mLastNDistanceMarker;
				mLastNDistanceMarker += mDistanceIncrement;
	    	}
	    	var mLapTimerTime = (info.timerTime != null) ? info.timerTime - mLastLapTimeMarker : 0.0;
	    	var mCurrentHeartRate		= (info.currentHeartRate != null) ? info.currentHeartRate : 0;
	    	var mAverageHeartRate		= (info.averageHeartRate != null) ? info.averageHeartRate : 0;
	    	mLapHeartRateAccumulator   += mCurrentHeartRate;
	    	var mLapHeartRate 			= (mLapHeartRateAccumulator / mLapTicker).toNumber();

	    	if (info.currentSpeed != null && info.currentSpeed < 1.8) { //! Speed below which the moving time timer is paused (1.8 m/s = 9:15 min/km, ~15:00 min/mi)
				//! Simple non-moving time calculation - relies on compute() being called every second
				mStoppedTime++;
				mStoppedDistance += mDistanceIncrement;
			}			

			//! Running economy: http://fellrnr.com/wiki/Running_Economy
			//! Averaged over the last 30 seconds, with the caveat that an exponential moving average
			//! is used for the heart rate data (saves memory versus storing N HR values)
			//! \-> Decay factor alpha set at 2/(N+1); N=30, alpha and 1-alpha have been pre-computed
	        if (mLastNAvgHeartRate == 0.0) {
	        	mLastNAvgHeartRate = mCurrentHeartRate;
	        	mLastNEconomy = 0.0;
	        } else {
	        	mLastNAvgHeartRate = (0.064516 * mCurrentHeartRate) + (0.935484 * mLastNAvgHeartRate);
				if (mLastNElapsedDistance > 0) {
					var t = (mTicker < 30) ? mTicker / 30.0 : 0.5;
					mLastNEconomy = ( 1 / ( ((mLastNAvgHeartRate - uRestingHeartRate) * t) / (mLastNElapsedDistance / 1609.344) ) ) * 100000;
				}
	        }
	        mEconomyField.setData(mLastNEconomy.toNumber());

	        var mAverageEconomy = 0;
	        if (mAverageHeartRate > uRestingHeartRate
	        	&& info.timerTime > 1000
	        	&& mElapsedDistance > 0) {
	        	mAverageEconomy = ( 1 / ( ( (mAverageHeartRate - uRestingHeartRate) * (info.timerTime / 60000.0) ) / (mElapsedDistance / 1609.344) ) ) * 100000;
	        }
	        mAverageEconomyField.setData(mAverageEconomy.toNumber());

	        var mLapEconomy = 0;
	        if (mLapHeartRate > uRestingHeartRate
	        	&& info.timerTime > 1000
	        	&& mLapElapsedDistance > 0) {
	        	mLapEconomy = ( 1 / ( ( (mLapHeartRate - uRestingHeartRate) * (mLapTimerTime / 60000.0) ) / ( mLapElapsedDistance / 1609.344) ) ) * 100000;
	        }
	        mLapEconomyField.setData(mLapEconomy.toNumber());
	        
	        mPrevElapsedDistance = mElapsedDistance;
    	}		
    }

    //! Store last lap quantities and set lap markers
    function onTimerLap() {
    	var info = Activity.getActivityInfo();

    	mLastLapTimerTime			= (info.timerTime - mLastLapTimeMarker) / 1000;
    	mLastLapElapsedDistance		= (info.elapsedDistance != null) ? info.elapsedDistance - mLastLapDistMarker : 0;
    	//mLastLapHeartRate 			= mLapHeartRate;
    	//mLastLapEconomy				= mLapEconomy;

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
    	mLapTicker = 0;
    	mLastLapDistMarker 			= info.elapsedDistance;
    	mLastLapTimeMarker 			= info.timerTime;
    	mLastLapStoppedTimeMarker	= mStoppedTime;
    	mLastLapStoppedDistMarker	= mStoppedDistance;
    	mLapHeartRateAccumulator 	= 0;
    	
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


    //! Current activity is ended
    function onTimerReset() {
    	mLaps = 1;
    }


    //! Do necessary calculations and draw fields.
    //! This will be called once a second when the data field is visible.
    function onUpdate(dc) {
    	var info = Activity.getActivityInfo();

    	var mColour;
    	var labelColour;

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
    	var mMovingSpeed = (info.averageSpeed != null) ? info.averageSpeed : 0.0;
    	var mLapMovingSpeed = mLapSpeed;
    	var mLapStoppedTime = mStoppedTime - mLastLapStoppedTimeMarker;

    	if (mTimerTime > 0
    		&& mStoppedTime > 0
    		&& mStoppedTime < mTimerTime
    		&& info.elapsedDistance != null) {
    		mMovingSpeed = (info.elapsedDistance - mStoppedDistance) / (mTimerTime - mStoppedTime);
		}

		if (mLapTimerTime > 0
    		&& mLapStoppedTime > 0
    		&& mLapStoppedTime < mLapTimerTime) {
    		mLapMovingSpeed = (mLapElapsedDistance - (mStoppedDistance - mLastLapStoppedDistMarker)) / (mLapTimerTime - mLapStoppedTime);
		}

    	//! Calculate HR zone
    	var mHrZone = 0.0;
    	var mCurrentHeartRate = "--";
    	if (info.currentHeartRate != null) {
    		mCurrentHeartRate = info.currentHeartRate;
			if (uHrZones != null) {
		    	if (info.currentHeartRate < uHrZones[0]) {
					mHrZone = info.currentHeartRate / uHrZones[0].toFloat();
				} else if (info.currentHeartRate < uHrZones[1]) {
					mHrZone = 1 + (info.currentHeartRate - uHrZones[0]) / (uHrZones[1] - uHrZones[0]).toFloat();
				} else if (info.currentHeartRate < uHrZones[2]) {
					mHrZone = 2 + (info.currentHeartRate - uHrZones[1]) / (uHrZones[2] - uHrZones[1]).toFloat();
				} else if (info.currentHeartRate < uHrZones[3]) {
					mHrZone = 3 + (info.currentHeartRate - uHrZones[2]) / (uHrZones[3] - uHrZones[2]).toFloat();
				} else if (info.currentHeartRate < uHrZones[4]) {
					mHrZone = 4 + (info.currentHeartRate - uHrZones[3]) / (uHrZones[4] - uHrZones[3]).toFloat();
				} else {
					mHrZone = 5 + (info.currentHeartRate - uHrZones[4]) / (uHrZones[5] - uHrZones[4]).toFloat();
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
		dc.fillRectangle(0, 64, 66, 17);
		dc.setColor(labelColour, Graphics.COLOR_TRANSPARENT);
		dc.drawText(33, 71, Graphics.FONT_XTINY, (uHrDisplay) ? "HR Zone" : "HR", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

		//! Cadence zone indicator colour (fixed thresholds and colours to match Garmin, with the addition of grey for walking/stopped)
		labelColour = Graphics.COLOR_BLACK;
		var labelText = "";
		if (!uCentreRightMetric) {
			mColour = Graphics.COLOR_LT_GRAY;
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
			dc.fillRectangle(149, 64, 66, 17);
			labelText = "Cadence";
		} else { //if (uCentreRightMetric) {
			labelText = "Economy";
		}
		dc.setColor(labelColour, Graphics.COLOR_TRANSPARENT);
		dc.drawText(181, 71, Graphics.FONT_XTINY, labelText, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

		//! Current pace vs target pace colour indicator
		mColour = Graphics.COLOR_LT_GRAY;
		labelColour = Graphics.COLOR_BLACK;
		if (info.currentSpeed != null && info.currentSpeed > 1.8) {	//! Only use the pace colour indicator when running (1.8 m/s = 9:15 min/km, ~15:00 min/mi)
			var mTargetSpeed = 0.0;
			if (uTargetPaceMetric == 0 && info.averageSpeed != null) {
				mTargetSpeed = info.averageSpeed;
			} else if (uTargetPaceMetric == 1) {
				mTargetSpeed = mMovingSpeed;
			} else if (uTargetPaceMetric == 2) {
				mTargetSpeed = mLapSpeed;
			} else if (uTargetPaceMetric == 3) {
				mTargetSpeed = mLapMovingSpeed;
			} else if (uTargetPaceMetric == 4) {
				mTargetSpeed = mLastLapSpeed;
			} else if (uTargetPaceMetric == 5) {
				mTargetSpeed = mLastLapMovingSpeed;
			}
			if (mTargetSpeed > 0) {
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
		}
		dc.setColor(mColour, Graphics.COLOR_TRANSPARENT);
		dc.fillRectangle(66, 64, 83, 17);
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
		dc.drawLine(66, 63, 66, 122);
		dc.drawLine(149, 63, 149, 122);
    	
		//! Bottom vertical divider
		dc.drawLine(107, 122, 107, 180);

		//! Top centre mini-field separator
		var x = 96;
		var width = 25;
		if (mLaps > 9) {
			x = 92;
			width = 32;
		}
		dc.drawRoundedRectangle(x, -10, width, 36, 4);

        //!
        //! Draw fields
        //! ===========
        //!

        //! Set text colour
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);

		dc.drawText(107, -4, Graphics.FONT_NUMBER_MILD, mLaps, Graphics.TEXT_JUSTIFY_CENTER);
		
		//! Top row left: time
		var mTime = mTimerTime;
		var lTime = "Timer";
		/*
		if (uTimerDisplay == 0) {
			mTime = mTimerTime;
			lTime = "Timer";
		} else
		/**/
		if (uTimerDisplay == 1) {
			mTime = mTimerTime - mStoppedTime;
			lTime = "Running";
		} else if (uTimerDisplay == 2) {
			mTime = (info.elapsedTime != null) ? info.elapsedTime / 1000 : 0;
			lTime = "Elapsed";
		} else if (uTimerDisplay == 3) {
			mTime = mLapTimerTime;
			lTime = "Lap Time";
		} else if (uTimerDisplay == 4) {
			mTime = mLastLapTimerTime;
			lTime = "Last Lap";
		} else if (uTimerDisplay == 5) {
			mTime = mTimerTime / mLaps;
			lTime = "Avg. Lap";
		}

		var fTimerSecs = (mTime % 60).format("%02d");
		var fTimer;        
    	if (mTime > 3599) {
    		//! Format time as h:mm(ss) if more than an hour
    		fTimer = (mTime / 3600).format("%d") + ":" + (mTime / 60 % 60).format("%02d");
    		x = 48;
			dc.drawText(80, 36, Graphics.FONT_NUMBER_MILD, fTimerSecs, Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
		} else {
			//! Format time as m:ss
			fTimer = (mTime / 60).format("%d") + ":" + fTimerSecs;
			x = 61;
		}
		dc.drawText(x, 41, Graphics.FONT_NUMBER_MEDIUM, fTimer, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		dc.drawText(62, 15, Graphics.FONT_XTINY,  lTime, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

		//! Top row right: distance
		var mDistance = (info.elapsedDistance != null) ? info.elapsedDistance / unitD : 0;
		var lDistance = "Distance";
		/*
		if (uDistDisplay == 0) {
			mDist = (info.elapsedDistance != null) ? info.elapsedDistance / unitD : 0;
			lDist = "Distance";
		} else
		/**/
		if (uDistDisplay == 1) {
			mDistance = (info.elapsedDistance != null) ? (info.elapsedDistance - mStoppedDistance) / unitD : 0;
			lDistance = "Run. Dist.";
		} else if (uDistDisplay == 2) {
			mDistance = mLapElapsedDistance / unitD;
			lDistance = "Lap Dist.";
		} else if (uDistDisplay == 3) {
			mDistance = mLastLapElapsedDistance / unitD;
			lDistance = "L-1 Dist.";
		} else if (uDistDisplay == 4) {
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
		
		//! Centre middle: current pace
		if (info.currentSpeed == null || info.currentSpeed < 0.447164) {
			drawSpeedUnderlines(dc, 107, 99);
		} else {		
			dc.drawText(107, 100, Graphics.FONT_NUMBER_MEDIUM, fmtPace(unitP/(Math.round((unitP/info.currentSpeed) / 5) * 5)), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}

		//! Centre left: heart rate
		dc.drawText(31, 100, Graphics.FONT_NUMBER_MEDIUM, (uHrDisplay) ? mHrZone.format("%.1f") : mCurrentHeartRate, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

		//! Centre right: cadence or economy
		var fCentre = "";
		if (!uCentreRightMetric) {
			fCentre = (info.currentCadence != null) ? info.currentCadence : 0;
		} else { //if (uCentreRightMetric) {
			fCentre = mLastNEconomy.format("%d");
		}
		dc.drawText(180, 100, Graphics.FONT_NUMBER_MEDIUM, fCentre, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

		//! Bottom left
		var fPace = 0.0;
		var lPace = "Avg. Pace";
		if (uBottomLeftMetric == 0 && info.averageSpeed != null) {
			fPace = info.averageSpeed;
			//lPace = "Avg. Pace";
		} else if (uBottomLeftMetric == 1) {
			fPace = mMovingSpeed;
			lPace = "Run. Pace";
		} else if (uBottomLeftMetric == 2) {
			fPace = mLapSpeed;
			lPace = "Lap Pace";
		} else if (uBottomLeftMetric == 3) {
			fPace = mLapMovingSpeed;
			lPace = "Lap R Pace";
		} else if (uBottomLeftMetric == 4) {
			fPace = mLastLapSpeed;
			lPace = "L-1 Pace";
		} else if (uBottomLeftMetric == 5) {
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
		if (uBottomRightMetric == 0 && info.averageSpeed != null) {
			fPace = info.averageSpeed;
			//lPace = "Avg. Pace";
		} else if (uBottomRightMetric == 1) {
			fPace = mMovingSpeed;
			lPace = "Run. Pace";
		} else if (uBottomRightMetric == 2) {
			fPace = mLapSpeed;
			lPace = "Lap Pace";
		} else if (uBottomRightMetric == 3) {
			fPace = mLapMovingSpeed;
			lPace = "Lap R Pace";
		} else if (uBottomRightMetric == 4) {
			fPace = mLastLapSpeed;
			lPace = "L-1 Pace";
		} else if (uBottomRightMetric == 5) {
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
