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

    hidden var uHrZones                     = [ 93, 111, 130, 148, 167, 185 ];
    hidden var uWeight                      = 0;
    hidden var unitP                        = 1000.0;
    hidden var unitD                        = 1000.0;

    hidden var uTimerDisplay                = 0;
    //! 0 => Timer
    //! 1 => Moving (timer) time
    //! 2 => Lap time
    //! 3 => Last lap time
    //! 4 => Average lap time

    hidden var uDistDisplay                 = 0;
    //! 0 => Total distance
    //! 1 => Moving distance
    //! 2 => Lap distance
    //! 3 => Last lap distance

    hidden var uRoundedPace                 = true;
    //! true     => Show current pace as Rounded Pace (i.e. rounded to 5 second intervals)
    //! false    => Show current pace without rounding (i.e. 1-second resolution)

    hidden var uBacklight                   = false;
    //! true     => Force the backlight to stay on permanently
    //! false    => Use the defined backlight timeout as normal

    hidden var uBottomLeftMetric            = 1;    //! Data to show in bottom left field
    hidden var uBottomRightMetric           = 0;    //! Data to show in bottom right field
    //! Lower fields enum:
    //! 0 => (overall) average pace
    //! 1 => Moving (running) pace
    //! 2 => Lap pace
    //! 3 => Lap moving (running) pace
    //! 4 => Last lap pace
    //! 5 => Last lap moving (running) pace
    //! 6 => Recent economy
    //! 7 => Energy expenditure

    hidden var mTimerRunning                = false;
    hidden var mStartStopPushed             = 0;    //! Timer value when the start/stop button was last pushed

    hidden var mStoppedTime                 = 0;
    hidden var mStoppedDistance             = 0;
    hidden var mPrevElapsedDistance         = 0;

    //! Which average pace metric should be used as the reference for deviation of the current pace? (see above)
    hidden var uTargetPaceMetric            = 0;

    hidden var mLaps                        = 1;
    hidden var mLastLapDistMarker           = 0;
    hidden var mLastLapTimeMarker           = 0;
    hidden var mLastLapStoppedTimeMarker    = 0;
    hidden var mLastLapStoppedDistMarker    = 0;

    hidden var mLastLapTimerTime            = 0;
    hidden var mLastLapElapsedDistance      = 0;
    hidden var mLastLapMovingSpeed          = 0;
    hidden var mLastLapCalories             = 0;

    hidden var mEconomySmooth               = 0;
    hidden var mEconomyField                = null;
    hidden var mAverageEconomyField         = null;
    hidden var mLapEconomyField             = null;

    function initialize() {
        DataField.initialize();

        uHrZones = UserProfile.getHeartRateZones(UserProfile.getCurrentSport());
        var mProfile = UserProfile.getProfile();
        if (mProfile != null) {
             uWeight  = mProfile.weight / 1000.0;
         }

         var mApp = Application.getApp();
         uTimerDisplay       = mApp.getProperty("pTimerDisplay");
         uDistDisplay        = mApp.getProperty("pDistDisplay");
         uTargetPaceMetric   = mApp.getProperty("pTargetPace");
         uBottomLeftMetric   = mApp.getProperty("pBottomLeftMetric");
         uBottomRightMetric  = mApp.getProperty("pBottomRightMetric");
         uRoundedPace        = mApp.getProperty("pRoundedPace");

        if (System.getDeviceSettings().paceUnits == System.UNIT_STATUTE) {
            unitP = 1609.344;
        }

        if (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE) {
            unitD = 1609.344;
        }

        mEconomyField           = createField("running_economy", 0, FitContributor.DATA_TYPE_UINT16, { :mesgType=>FitContributor.MESG_TYPE_RECORD,  :units=>"cal/kg/km" });
        mAverageEconomyField    = createField("average_economy", 1, FitContributor.DATA_TYPE_UINT16, { :mesgType=>FitContributor.MESG_TYPE_SESSION, :units=>"cal/kg/km" });
        mLapEconomyField        = createField("lap_economy",     2, FitContributor.DATA_TYPE_UINT16, { :mesgType=>FitContributor.MESG_TYPE_LAP,     :units=>"cal/kg/km" });

        mEconomyField.setData(0);
        mAverageEconomyField.setData(0);
        mLapEconomyField.setData(0);
    }


    //! Calculations we need to do every second even when the data field is not visible
    function compute(info) {
        if (mTimerRunning) {  //! We only do some calculations if the timer is running

            var mElapsedDistance    = (info.elapsedDistance != null) ? info.elapsedDistance : 0.0;
            var mDistanceIncrement  = mElapsedDistance - mPrevElapsedDistance;
            var mLapElapsedDistance = mElapsedDistance - mLastLapDistMarker;

            if (info.currentSpeed != null && info.currentSpeed < 2.0) { //! Speed below which the moving time timer is paused (2.0 m/s = 8:20 min/km, 13:25 min/mi)
                //! Simple non-moving time calculation - relies on compute() being called every second
                mStoppedTime++;
                mStoppedDistance += mDistanceIncrement;
            }

            var mAverageEconomy = 0;
            if (info has :calories && info.calories != null && info.calories > 0 && mElapsedDistance > 0 && uWeight > 0) {
                mAverageEconomy = ( (info.calories * 1000.0) / uWeight) / (mElapsedDistance / 1000.0);   //! cal kg-1 km-1 - Note, cal not kcal!
            }
            mAverageEconomyField.setData(mAverageEconomy.toNumber());

            var mLapEconomy = 0;
            if (info has :calories && info.calories != null && info.calories > mLastLapCalories && mLapElapsedDistance > 0 && uWeight > 0) {
                mLapEconomy = ( ( (info.calories - mLastLapCalories) * 1000.0 ) / uWeight ) / (mLapElapsedDistance / 1000.0);    //! cal kg-1 km-1 - Note, cal not kcal!
            }
            mLapEconomyField.setData(mLapEconomy.toNumber());

            mPrevElapsedDistance = mElapsedDistance;

            //! If enabled, switch the backlight on in order to make it stay on
            if (uBacklight) {
                Attention.backlight(true);
            }
        }

        var mEconomy = 0;
        if (info has :energyExpenditure && uWeight > 0) {
            if (info.energyExpenditure == null || info.energyExpenditure == 0) {
                //! If there's no EE data, set economy to zero
                mEconomy = 0;
                mEconomySmooth = 0;
            } else if (info.currentSpeed != null && info.currentSpeed > 0.8 && info.currentSpeed < 18) {
                //! Calculate economy so long as the speed seems normal
                mEconomy = ( ( info.energyExpenditure  / uWeight ) / info.currentSpeed ) * 16666.666; //! cal kg-1 km-1 - Note, cal not kcal!
            } else {
                //! Otherwise, propagate the existing economy value (to avoid erroneous spikes)
                mEconomy = mEconomySmooth;
            }
        }

        if (mEconomySmooth == 0) {
            //! If we have a raw instantaneous economy but the smoothed value is zero, initialize the rolling average by setting it to the instantaneous value
            mEconomySmooth = mEconomy;
        } else {
            //! Smoothing roughly equivalent to 5s average
            mEconomySmooth = (0.333333 * mEconomy) + (0.666666 * mEconomySmooth);
        }
        //! Cap the economy at four figures
        if (mEconomySmooth > 9999) {
            mEconomySmooth = 9999;
        }
        mEconomyField.setData(mEconomySmooth.toNumber());    //! Store smoothed value

    }

    //! Store last lap quantities and set lap markers
    function onTimerLap() {
        var info = Activity.getActivityInfo();

        mLastLapTimerTime        = (info.timerTime - mLastLapTimeMarker) / 1000;
        mLastLapElapsedDistance  = (info.elapsedDistance != null) ? info.elapsedDistance - mLastLapDistMarker : 0;
        mLastLapCalories         = (info has :calories  && info.calories != null)  ? info.calories  : 0.0;

        var mLastLapStoppedTime        = mStoppedTime - mLastLapStoppedTimeMarker;
        var mLastLapStoppedDistance    = mStoppedDistance - mLastLapStoppedDistMarker;
        if (mLastLapStoppedTime < mLastLapTimerTime && mLastLapStoppedDistance < mLastLapElapsedDistance) {
            mLastLapMovingSpeed = (mLastLapElapsedDistance - mLastLapStoppedDistance) / (mLastLapTimerTime - mLastLapStoppedTime);
        } else {
            mLastLapMovingSpeed = (mLastLapTimerTime > 0) ? mLastLapElapsedDistance / mLastLapTimerTime : 0.0;
        }

        mLaps++;
        mLastLapDistMarker           = info.elapsedDistance;
        mLastLapTimeMarker           = info.timerTime;
        mLastLapStoppedTimeMarker    = mStoppedTime;
        mLastLapStoppedDistMarker    = mStoppedDistance;

    }

    //! Timer transitions from stopped to running state
    function onTimerStart() {
        var info = Activity.getActivityInfo();
        //! If the start/stop button was last pushed less than 1.5 seconds ago,
        //! toggle the force backlight feature (see in compute(), above).
        //! That is, press the start/stop button twice in quick succession
        //! to make the backlight stay on, or revert to the normal timeout
        //! setting as configured on the watch.
        if (  ( info.elapsedTime > 0 )  &&  ( (info.elapsedTime - mStartStopPushed) < 1500 )  ) {
            uBacklight = !uBacklight;
        }
        mStartStopPushed = info.elapsedTime;
        mTimerRunning = true;
    }


    //! Timer transitions from running to stopped state
    function onTimerStop() {
        var info = Activity.getActivityInfo();
        mStartStopPushed = info.elapsedTime;
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
        mStoppedTime                = 0;
        mStoppedDistance            = 0;
        mPrevElapsedDistance        = 0;

        mLaps                       = 1;
        mLastLapDistMarker          = 0;
        mLastLapTimeMarker          = 0;
        mLastLapStoppedTimeMarker   = 0;
        mLastLapStoppedDistMarker   = 0;

        mLastLapTimerTime           = 0;
        mLastLapElapsedDistance     = 0;
        mLastLapMovingSpeed         = 0;
        mLastLapCalories            = 0;

        mEconomySmooth              = 0;

        mStartStopPushed            = 0;
    }


    //! Do necessary calculations and draw fields.
    //! This will be called once a second when the data field is visible.
    function onUpdate(dc) {
        var info = Activity.getActivityInfo();

        var mColour;

        //! Calculate lap distance
        var mLapElapsedDistance = 0.0;
        if (info.elapsedDistance != null) {
            mLapElapsedDistance = info.elapsedDistance - mLastLapDistMarker;
        }

        //! Calculate lap time and convert timers from milliseconds to seconds
        var mTimerTime      = 0;
        var mLapTimerTime   = 0;

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

        var mEnergyExpenditure = (info.energyExpenditure != null) ? (info.energyExpenditure * 60).toNumber() : 0;
        var mCalories = (info.calories != null) ? info.calories : 0;

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
                    mColour = Graphics.COLOR_RED;        //! Maximum (Z5)
                } else if (mCurrentHeartRate >= uHrZones[3]) {
                    mColour = Graphics.COLOR_ORANGE;    //! Threshold (Z4)
                } else if (mCurrentHeartRate >= uHrZones[2]) {
                    mColour = Graphics.COLOR_GREEN;        //! Aerobic (Z3)
                } else if (mCurrentHeartRate >= uHrZones[1]) {
                    mColour = Graphics.COLOR_BLUE;        //! Easy (Z2)
                } //! Else Warm-up (Z1) and no zone both inherit default light grey here
            }
        }
        dc.setColor(mColour, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, 64, 66, 17);

        //! Cadence zone (fixed thresholds and colours to match Garmin Connect)
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
        dc.fillRectangle(149, 64, 66, 17);

        //! Current pace vs target pace colour indicator
        mColour = Graphics.COLOR_LT_GRAY;
        if (info.currentSpeed != null && info.currentSpeed > 2.0) {    //! Only use the pace colour indicator when running (2.0 m/s = 8:20 min/km, 13:25 min/mi)
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
                if (paceDeviation < 0.95) {    //! More than 5% slower
                    mColour = Graphics.COLOR_RED;
                } else if (paceDeviation <= 1.05) {    //! Within +/-5% of target pace
                    mColour = Graphics.COLOR_GREEN;
                } else {  //! More than 5% faster
                    mColour = Graphics.COLOR_BLUE;
                }
            }
        }
        dc.setColor(mColour, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(66, 64, 83, 17);

        //! Draw separator lines
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);

        //! Horizontal thirds
        dc.drawLine(0,   63,  215, 63);
        dc.drawLine(0,   122, 215, 122);

        //! Top vertical divider
        dc.drawLine(107, 26,  107, 63);

        //! Centre vertical dividers
        dc.drawLine(66,  63,  66,  122);
        dc.drawLine(149, 63,  149, 122);

        //! Bottom vertical divider
        dc.drawLine(107, 122, 107, 180);

        //! Top centre mini-field separator
        dc.drawRoundedRectangle(92, -10, 32, 36, 4);

        //! Set text colour
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);

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
        var x = 61;
        if (mTime > 3599) {
            //! (Re-)format time as h:mm(ss) if more than an hour
            fTimer = (mTime / 3600).format("%d") + ":" + (mTime / 60 % 60).format("%02d");
            x = 48;
            dc.drawText(80, 36, Graphics.FONT_NUMBER_MILD, fTimerSecs, Graphics.TEXT_JUSTIFY_LEFT|Graphics.TEXT_JUSTIFY_VCENTER);
        }
        dc.drawText(x, 41, Graphics.FONT_NUMBER_MEDIUM, fTimer, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(62, 15, Graphics.FONT_XTINY,  lTime, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

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
        dc.drawText(154, 41, Graphics.FONT_NUMBER_MEDIUM, mDistance.format(fString), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(156, 15, Graphics.FONT_XTINY,  lDistance, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

        //! Centre middle: current pace
        if (info.currentSpeed == null || info.currentSpeed < 0.447164) {
            drawSpeedUnderlines(dc, 107, 99);
        } else {
            var fCurrentPace = info.currentSpeed;
            if (uRoundedPace) {
                fCurrentPace = unitP/(Math.round( (unitP/info.currentSpeed) / 5 ) * 5);
            }
            dc.drawText(107, 100, Graphics.FONT_NUMBER_MEDIUM, fmtPace(fCurrentPace), Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
        }
        dc.drawText(107, 71, Graphics.FONT_XTINY,  "Pace", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

        //! Centre left: heart rate
        dc.drawText(31, 100, Graphics.FONT_NUMBER_MEDIUM, mCurrentHeartRate, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(33, 71, Graphics.FONT_XTINY, "HR", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

        //! Centre right: cadence
        dc.drawText(180, 100, Graphics.FONT_NUMBER_MEDIUM, (info.currentCadence != null) ? info.currentCadence : 0, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(181, 71, Graphics.FONT_XTINY, "Cadence", Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

        //! Bottom left
        var fieldValue     = 0.0;
        var fieldLabel     = "Avg. Pace";
        var isPace         = true;
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
            fieldValue = mEconomySmooth.format("%d");
            fieldLabel = "Economy";
            isPace = false;
        } else if (uBottomLeftMetric == 7) {
            fieldValue = mEnergyExpenditure;
            fieldLabel = "Energy Ex.";
            isPace = false;
        } else if (uBottomLeftMetric == 8) {
            fieldValue = mCalories;
            fieldLabel = "Calories";
            isPace = false;
        }
        if (isPace && fieldValue < 0.447164) {
            drawSpeedUnderlines(dc, 65, 139);
        } else {
            dc.drawText(63, 142, Graphics.FONT_NUMBER_MEDIUM, (isPace) ? fmtPace(fieldValue) : fieldValue, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
        }
        dc.drawText(72, 167, Graphics.FONT_XTINY, fieldLabel, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

        //! Bottom right
        fieldValue     = 0.0;
        fieldLabel     = "Avg. Pace";
        isPace         = true;
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
            fieldValue = mEconomySmooth.format("%d");
            fieldLabel = "Economy";
            isPace = false;
        } else if (uBottomRightMetric == 7) {
            fieldValue = mEnergyExpenditure;
            fieldLabel = "Energy Ex.";
            isPace = false;
        } else if (uBottomRightMetric == 8) {
            fieldValue = mCalories;
            fieldLabel = "Calories";
            isPace = false;
        }
        if (isPace && fieldValue < 0.447164) {
            drawSpeedUnderlines(dc, 150, 139);
        } else {
            dc.drawText(150, 142, Graphics.FONT_NUMBER_MEDIUM, (isPace) ? fmtPace(fieldValue) : fieldValue, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);
        }
        dc.drawText(141, 167, Graphics.FONT_XTINY, fieldLabel, Graphics.TEXT_JUSTIFY_CENTER|Graphics.TEXT_JUSTIFY_VCENTER);

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
