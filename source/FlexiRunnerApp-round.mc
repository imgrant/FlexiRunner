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

	hidden var uHrZones = [ 93, 111, 130, 148, 167, 185 ];
	hidden var unitP = 1000.0;
	hidden var unitD = 1000.0;

	hidden var uTimerDisplay = 0;
	//! 0 => Timer
	//! 1 => Moving (timer) time
	//! 2 => Lap time
	//! 3 => Last lap time
	//! 4 => Average lap time

	hidden var uDistDisplay = 0;
	//! 0 => Total distance
	//! 1 => Moving distance
	//! 2 => Lap distance
	//! 3 => Last lap distance

	hidden var uCentreRightMetric = false;
	//! false => Current cadence
	//! true  => Running economy (recent average over last N seconds)

	hidden var uRoundedPace = true;
	//! true 	=> Show current pace as Rounded Pace (i.e. rounded to 5 second intervals)
	//! false	=> Show current pace without rounding (i.e. 1-second resolution)

	hidden var uBottomLeftMetric  = 1;	//! Data to show in bottom left field
	hidden var uBottomRightMetric = 0;	//! Data to show in bottom right field
	//! Lower fields enum:
	//! 0 => (overall) average pace
	//! 1 => Moving (running) pace
	//! 2 => Lap pace
	//! 3 => Lap moving (running) pace
	//! 4 => Last lap pace
	//! 5 => Last lap moving (running) pace
	//! 6 => Recent economy
	//! 7 => Energy expenditure

	hidden var mTimerRunning = false;

	hidden var mStoppedTime 		= 0;
	hidden var mStoppedDistance 	= 0;
	hidden var mPrevElapsedDistance = 0;

	hidden var uTargetPaceMetric = 0;	//! Which average pace metric should be used as the reference for deviation of the current pace? (see above)

	hidden var mLaps 					 = 1;
	hidden var mLastLapDistMarker 		 = 0;
    hidden var mLastLapTimeMarker 		 = 0;
    hidden var mLastLapStoppedTimeMarker = 0;
    hidden var mLastLapStoppedDistMarker = 0;
    hidden var mLapHeartRateAccumulator  = 0;

	hidden var mLastLapTimerTime 		= 0;
	hidden var mLastLapElapsedDistance 	= 0;
	hidden var mLastLapMovingSpeed 		= 0;

	hidden var uRestingHeartRate 	= 60;
	hidden var mLastNDistanceMarker = 0;
	hidden var mLastNAvgHeartRate 	= 0;
	hidden var mLastNEconomySmooth	= 0;
	
	hidden var mTicker 		= 0;
	hidden var mLapTicker	= 0;

	hidden var mEconomyField 			= null;
	hidden var mAverageEconomyField 	= null;
	hidden var mLapEconomyField 		= null;
	hidden var mEnergyExpenditureField	= null;

    function initialize() {
        DataField.initialize();

        var mProfile = UserProfile.getProfile();
        if (mProfile != null) {
	 		uHrZones = UserProfile.getHeartRateZones(UserProfile.getCurrentSport());
	 		if (mProfile has :restingHeartRate && mProfile.restingHeartRate != null) {
	 			uRestingHeartRate = mProfile.restingHeartRate;
	 		}
 		}

 		var mApp = Application.getApp();
 		uTimerDisplay			= mApp.getProperty("pTimerDisplay");
 		uDistDisplay			= mApp.getProperty("pDistDisplay");
 		uTargetPaceMetric		= mApp.getProperty("pTargetPace");
 		uCentreRightMetric		= mApp.getProperty("pCentreRightMetric");
 		uBottomLeftMetric		= mApp.getProperty("pBottomLeftMetric");
 		uBottomRightMetric		= mApp.getProperty("pBottomRightMetric");
 		uRoundedPace			= mApp.getProperty("pRoundedPace");

        if (System.getDeviceSettings().paceUnits == System.UNIT_STATUTE) {
        	unitP = 1609.344;
        }

        if (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE) {
        	unitD = 1609.344;
        }

        mEconomyField 		 	= createField("running_economy", 	0, FitContributor.DATA_TYPE_UINT16, { :mesgType=>FitContributor.MESG_TYPE_RECORD });
        mAverageEconomyField 	= createField("average_economy", 	1, FitContributor.DATA_TYPE_UINT16, { :mesgType=>FitContributor.MESG_TYPE_SESSION });
        mLapEconomyField 	 	= createField("lap_economy", 	  	2, FitContributor.DATA_TYPE_UINT16, { :mesgType=>FitContributor.MESG_TYPE_LAP });
        mEnergyExpenditureField	= createField("energy_expenditure", 3, FitContributor.DATA_TYPE_UINT16, { :mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>"kcal/h" });
        
        mEconomyField.setData(0);
        mAverageEconomyField.setData(0);
        mLapEconomyField.setData(0);
        mEnergyExpenditureField.setData(0);
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
	        var mLastNEconomy = 0;
	        if (mLastNAvgHeartRate == 0.0) {
	        	mLastNAvgHeartRate = mCurrentHeartRate;
	        } else {
	        	mLastNAvgHeartRate = (0.064516 * mCurrentHeartRate) + (0.935484 * mLastNAvgHeartRate);
	        }
			if (mLastNElapsedDistance > 0 && mLastNAvgHeartRate > uRestingHeartRate) {
				var t = (mTicker < 30) ? mTicker / 60.0 : 0.5;
				mLastNEconomy = ( 1 / ( ((mLastNAvgHeartRate - uRestingHeartRate) * t) / (mLastNElapsedDistance / 1609.344) ) ) * 100000;
			}
	        mLastNEconomySmooth = (0.222222 * mLastNEconomy) + (0.777777 * mLastNEconomySmooth);
	        mEconomyField.setData(mLastNEconomySmooth.toNumber());

	        var mAverageEconomy = 0;
	        if (mAverageHeartRate > uRestingHeartRate
	        	&& mElapsedDistance > 0) {
	        	mAverageEconomy = ( 1 / ( ( (mAverageHeartRate - uRestingHeartRate) * (info.timerTime / 60000.0) ) / (mElapsedDistance / 1609.344) ) ) * 100000;
	        }
	        mAverageEconomyField.setData(mAverageEconomy.toNumber());

	        var mLapEconomy = 0;
	        if (mLapHeartRate > uRestingHeartRate
	        	&& mLapElapsedDistance > 0) {
	        	mLapEconomy = ( 1 / ( ( (mLapHeartRate - uRestingHeartRate) * (mLapTimerTime / 60000.0) ) / ( mLapElapsedDistance / 1609.344) ) ) * 100000;
	        }
	        mLapEconomyField.setData(mLapEconomy.toNumber());
	        
	        mPrevElapsedDistance = mElapsedDistance;
    	}
    	
    	if (info has :energyExpenditure) {
    		if (info.energyExpenditure != null) {
    			mEnergyExpenditureField.setData( (info.energyExpenditure * 60).toNumber() );
    		}
    	}		
    }

    //! Store last lap quantities and set lap markers
    function onTimerLap() {
    	var info = Activity.getActivityInfo();

    	mLastLapTimerTime			= (info.timerTime - mLastLapTimeMarker) / 1000;
    	mLastLapElapsedDistance		= (info.elapsedDistance != null) ? info.elapsedDistance - mLastLapDistMarker : 0;

    	var mLastLapStoppedTime		= mStoppedTime - mLastLapStoppedTimeMarker;
    	var mLastLapStoppedDistance	= mStoppedDistance - mLastLapStoppedDistMarker;
    	if (mLastLapStoppedTime < mLastLapTimerTime
    		&& mLastLapStoppedDistance < mLastLapElapsedDistance) {
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
	    mStoppedTime 		 = 0;
		mStoppedDistance 	 = 0;
		mPrevElapsedDistance = 0;

		mLaps 					  = 1;
		mLastLapDistMarker 		  = 0;
	    mLastLapTimeMarker 		  = 0;
	    mLastLapStoppedTimeMarker = 0;
	    mLastLapStoppedDistMarker = 0;
	    mLapHeartRateAccumulator  = 0;

		mLastLapTimerTime 			= 0;
		mLastLapElapsedDistance 	= 0;
		mLastLapMovingSpeed 		= 0;

		mLastNDistanceMarker = 0;
		mLastNAvgHeartRate 	 = 0;
		mLastNEconomySmooth	 = 0;
		
		mTicker 	= 0;
		mLapTicker	= 0;
    }
    
    
    //! Do necessary calculations and draw fields.
    //! This will be called once a second when the data field is visible.
    function onUpdate(dc) {
    	var info = Activity.getActivityInfo();

		var mBgColour = (getBackgroundColor() == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
    	var mColour;

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

    	if (mStoppedTime < mTimerTime
    		&& info.elapsedDistance != null) {
    		mMovingSpeed = (info.elapsedDistance - mStoppedDistance) / (mTimerTime - mStoppedTime);
		}

		if (mLapStoppedTime < mLapTimerTime) {
    		mLapMovingSpeed = (mLapElapsedDistance - (mStoppedDistance - mLastLapStoppedDistMarker)) / (mLapTimerTime - mLapStoppedTime);
		}

     	//!
    	//! Draw colour indicators
		//!
		
    	//! HR zone
    	mColour = Graphics.COLOR_LT_GRAY; //! No zone default light grey
    	var mCurrentHeartRate = "--";
    	if (info.currentHeartRate != null) {
    		mCurrentHeartRate = info.currentHeartRate;
			if (uHrZones != null) {
				if (mCurrentHeartRate >= uHrZones[4]) {
					mColour = Graphics.COLOR_RED;		//! Maximum (Z5)
				} else if (mCurrentHeartRate >= uHrZones[3]) {
					mColour = Graphics.COLOR_ORANGE;	//! Threshold (Z4)
				} else if (mCurrentHeartRate >= uHrZones[2]) {
					mColour = Graphics.COLOR_GREEN;		//! Aerobic (Z3)
				} else if (mCurrentHeartRate >= uHrZones[1]) {
					mColour = Graphics.COLOR_BLUE;		//! Easy (Z2)
				} //! Else Warm-up (Z1) and no zone both inherit default light grey here
			}
    	}
    	dc.setColor(mColour, Graphics.COLOR_TRANSPARENT);
		dc.fillRectangle(0, 79, 66, 17);	

		//! Cadence zone (fixed thresholds and colours to match Garmin Connect)
		if (!uCentreRightMetric) {
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
				} //! Else no cadence or walking/stopped inherits default light grey here
			}
			dc.setColor(mColour, Graphics.COLOR_TRANSPARENT);
			dc.fillRectangle(149, 79, 70, 17);
		}

		//! Current pace vs target pace colour indicator
		mColour = Graphics.COLOR_LT_GRAY;
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
				if (paceDeviation < 0.95) {	//! More than 5% slower
					mColour = Graphics.COLOR_RED;
				} else if (paceDeviation <= 1.05) {	//! Within +/-5% of target pace
					mColour = Graphics.COLOR_GREEN;
				} else {  //! More than 5% faster
					mColour = Graphics.COLOR_BLUE;
				}
			}
		}
		dc.setColor(mColour, Graphics.COLOR_TRANSPARENT);
		dc.fillRectangle(66, 79, 83, 17);

    	//! Draw separator lines
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);

        //! Horizontal thirds
		dc.drawLine(0, 79, 215, 79);
		dc.drawLine(0, 142, 215, 142);

		//! Top vertical divider
		dc.drawLine(107, 26, 107, 79);

		//! Centre vertical dividers
		dc.drawLine(66, 79, 66, 142);
		dc.drawLine(149, 79, 149, 142);
    	
		//! Bottom vertical divider
		dc.drawLine(107, 142, 107, 218);

		//! Top centre mini-field separator
		dc.drawRoundedRectangle(92, -8, 32, 36, 4);

		//! Set text colour
        dc.setColor(mBgColour, Graphics.COLOR_TRANSPARENT);

        //!
        //! Draw field values
        //! =================
        //!        

        //! Lap counter
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
			mTime = mLapTimerTime;
			lTime = "Lap Time";
		} else if (uTimerDisplay == 3) {
			mTime = mLastLapTimerTime;
			lTime = "Last Lap";
		} else if (uTimerDisplay == 4) {
			mTime = mTimerTime / mLaps;
			lTime = "Avg. Lap";
		}

		var fTimerSecs = (mTime % 60).format("%02d");
		var fTimer = (mTime / 60).format("%d") + ":" + fTimerSecs;  //! Format time as m:ss
		var x = 64;        
    	if (mTime > 3599) {
    		//! (Re-)format time as h:mm(ss) if more than an hour
    		fTimer = (mTime / 3600).format("%d") + ":" + (mTime / 60 % 60).format("%02d");
    		x = 51;
			dc.drawText(82, 47, Graphics.FONT_NUMBER_MILD, fTimerSecs, Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
		}
		dc.drawText(x, 53, Graphics.FONT_NUMBER_MEDIUM, fTimer, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		dc.drawText(64, 27, Graphics.FONT_XTINY,  lTime, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

		//! Top row right: distance
		var mDistance = (info.elapsedDistance != null) ? info.elapsedDistance / unitD : 0;
		var lDistance = "Distance";
		/*
		if (uDistDisplay == 0) {
			mDistance = (info.elapsedDistance != null) ? info.elapsedDistance / unitD : 0;
			lDistance = "Distance";
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
		}

		var fString = "%.2f";
	 	if (mDistance > 100) {
	 		fString = "%.1f";
	 	}
		dc.drawText(154, 53, Graphics.FONT_NUMBER_MEDIUM, mDistance.format(fString), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		dc.drawText(154, 27, Graphics.FONT_XTINY,  lDistance, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		
		//! Centre middle: current pace
		if (info.currentSpeed == null || info.currentSpeed < 0.447164) {
			drawSpeedUnderlines(dc, 107, 119);
		} else {
			var fCurrentPace = info.currentSpeed;		
			if (uRoundedPace) {
				fCurrentPace = unitP/(Math.round( (unitP/info.currentSpeed) / 5 ) * 5);
			}
			dc.drawText(107, 116, Graphics.FONT_NUMBER_MEDIUM, fmtPace(fCurrentPace), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}
		dc.drawText(107, 87, Graphics.FONT_XTINY,  "Pace", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

		//! Centre left: heart rate
		dc.drawText(31, 116, Graphics.FONT_NUMBER_MEDIUM, mCurrentHeartRate, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		dc.drawText(33, 87, Graphics.FONT_XTINY, "HR", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

		//! Centre right: cadence or economy
		var fCentre = mLastNEconomySmooth.format("%d");
		var lCentre = "Economy";
		if (!uCentreRightMetric) {
			fCentre = (info.currentCadence != null) ? info.currentCadence : 0;
			lCentre = "Cadence";
		}
		dc.drawText(180, 116, Graphics.FONT_NUMBER_MEDIUM, fCentre, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		dc.drawText(181, 87, Graphics.FONT_XTINY, lCentre, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

		//! Bottom left
		var fieldValue 	= 0.0;
		var fieldLabel 	= "Avg. Pace";
		var isPace 		= true;
		if (uBottomLeftMetric == 0 && info.averageSpeed != null) {
			fieldValue = info.averageSpeed;
			//fieldLabel = "Avg. Pace";
		} else if (uBottomLeftMetric == 1) {
			fieldValue = mMovingSpeed;
			fieldLabel = "Run. Pace";
		} else if (uBottomLeftMetric == 2) {
			fieldValue = mLapSpeed;
			fieldLabel = "Lap Pace";
		} else if (uBottomLeftMetric == 3) {
			fieldValue = mLapMovingSpeed;
			fieldLabel = "Lap R Pace";
		} else if (uBottomLeftMetric == 4) {
			fieldValue = mLastLapSpeed;
			fieldLabel = "L-1 Pace";
		} else if (uBottomLeftMetric == 5) {
			fieldValue = mLastLapMovingSpeed;
			fieldLabel = "L-1 R Pace";
		} else if (uBottomLeftMetric == 6) {
			fieldValue = mLastNEconomySmooth.format("%d");
			fieldLabel = "Economy";
			isPace = false;
		} else if (uBottomLeftMetric == 7) {
			fieldValue = (info.energyExpenditure != null) ? (info.energyExpenditure * 60).toNumber() : 0;
			fieldLabel = "Energy Ex.";
			isPace = false;
		}
		if (isPace && fieldValue < 0.447164) {
			drawSpeedUnderlines(dc, 65, 162);
		} else {
			dc.drawText(63, 161, Graphics.FONT_NUMBER_MEDIUM, (isPace) ? fmtPace(fieldValue) : fieldValue, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}
		dc.drawText(73, 190, Graphics.FONT_XTINY, fieldLabel, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

		//! Bottom right
		fieldValue 	= 0.0;
		fieldLabel 	= "Avg. Pace";
		isPace 		= true;
		if (uBottomRightMetric == 0 && info.averageSpeed != null) {
			fieldValue = info.averageSpeed;
			//fieldLabel = "Avg. Pace";
		} else if (uBottomRightMetric == 1) {
			fieldValue = mMovingSpeed;
			fieldLabel = "Run. Pace";
		} else if (uBottomRightMetric == 2) {
			fieldValue = mLapSpeed;
			fieldLabel = "Lap Pace";
		} else if (uBottomRightMetric == 3) {
			fieldValue = mLapMovingSpeed;
			fieldLabel = "Lap R Pace";
		} else if (uBottomRightMetric == 4) {
			fieldValue = mLastLapSpeed;
			fieldLabel = "L-1 Pace";
		} else if (uBottomRightMetric == 5) {
			fieldValue = mLastLapMovingSpeed;
			fieldLabel = "L-1 R Pace";
		} else if (uBottomRightMetric == 6) {
			fieldValue = mLastNEconomySmooth.format("%d");
			fieldLabel = "Economy";
			isPace = false;
		} else if (uBottomRightMetric == 7) {
			fieldValue = (info.energyExpenditure != null) ? (info.energyExpenditure * 60).toNumber() : 0;
			fieldLabel = "Energy Ex.";
			isPace = false;
		}
		if (isPace && fieldValue < 0.447164) {
			drawSpeedUnderlines(dc, 150, 162);
		} else {
			dc.drawText(150, 161, Graphics.FONT_NUMBER_MEDIUM, (isPace) ? fmtPace(fieldValue) : fieldValue, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
		}
		dc.drawText(140, 190, Graphics.FONT_XTINY, fieldLabel, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

    }


    function fmtPace(secs) {
    	var s = (unitP/secs).toLong();
        return (s / 60).format("%0d") + ":" + (s % 60).format("%02d");
    }


    function drawSpeedUnderlines(dc, x, y) {
    	var y2 = y + 18;
        dc.setPenWidth(1);
    	dc.drawLine(x - 39, y2, x - 22, y2);
		dc.drawLine(x - 21, y2, x - 4,  y2);
		dc.drawLine(x + 4,  y2, x + 21, y2);
		dc.drawLine(x + 22, y2, x + 39, y2);
		dc.drawText(x, y, Graphics.FONT_NUMBER_MEDIUM, ":", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
    }

}
