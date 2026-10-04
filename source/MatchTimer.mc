// ============================================================
// MatchTimer.mc
//
// Match / interval timer for sports officials.
//
// Primary display is a COUNTDOWN from the selected interval
// (default 45 min) — the playing clock: SELECT starts and pauses
// it.  The COUNT-UP is the running clock: it starts with the
// first SELECT and never pauses, based at 00:00 (1st half) or at
// the interval (2nd half — e.g. counts up from 45:00 with 45-min
// intervals).  Only reset() (or an interval change, which resets)
// stops and zeroes it.
//
// start/pause preserves the countdown's elapsed time; reset()
// returns to the full interval, paused, count-up stopped.  Both
// clocks are System.getTimer() deltas, so no periodic callback is
// needed to keep time — the view only ticks to refresh the display.
//
// When the countdown reaches zero a one-shot Timer fires a
// distinct haptic alert; the countdown then holds at 00:00
// while the count-up keeps going (stoppage time).  While the
// countdown sits paused after a start, the same Timer repeats a
// gentle "clock stopped" reminder instead — the two jobs never
// overlap, so the app's Timer count doesn't grow.  A real Timer
// matters here: it fires with the display off, where the view's
// onUpdate (which used to poll the reminder) never runs.
//
// The STOPPAGE TIMER is a third, independent clock: an optional
// (default off) ad-hoc stopwatch for interruptions — injury, VAR,
// substitution.  A screen tap opens a stoppage segment, a second
// tap closes it and banks its elapsed into the half's stoppage
// total — the time the official adds on.  The readout is always
// that running total (banked + open segment).  It shares no state
// with the countdown or the count-up and never moves either of
// them; expiry closes an open segment, and only reset() (or an
// interval change) clears the total and the count.
//
// Two senses of "stoppage" meet in this file.  "Stoppage time"
// above is the countdown holding at 00:00 past the interval — an
// automatic consequence of expiry.  The Stoppage Timer is the
// hand-timed stopwatch below: separate state, separate code.
//
// Owned by the App (like BleManager) so match time survives
// BLE drops and reconnects.
// ============================================================

import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

const DEFAULT_INTERVAL_MIN = 45;

// While the countdown sits paused after having been started, buzz a
// gentle reminder this often.
const PAUSE_REMIND_MS = 20000;

class MatchTimer {

    hidden var _running          as Boolean = false;  // countdown (playing clock) running
    hidden var _elapsedMs        as Number  = 0;      // countdown ms accumulated to last pause
    hidden var _startTick        as Number  = 0;      // System.getTimer() at last countdown start
    hidden var _cuRunning        as Boolean = false;  // count-up (running clock) started
    hidden var _cuStartTick      as Number  = 0;      // System.getTimer() at the first start
    hidden var _intervalMs       as Number  = DEFAULT_INTERVAL_MIN * 60 * 1000;
    hidden var _secondHalf       as Boolean = false;  // count-up base = interval when true
    hidden var _hapticTimer      as Timer.Timer;      // running: one-shot expiry buzz
                                                      // paused:  repeating reminder
    hidden var _stoppageEnabled  as Boolean = false;  // tap-to-time-a-stoppage setting
    hidden var _stoppageOpen     as Boolean = false;  // a segment is being timed now
    hidden var _stoppageTick     as Number  = 0;      // getTimer() at the segment start
    hidden var _stoppageTotalMs  as Number  = 0;      // banked (closed) segments this half
    hidden var _stoppageCount    as Number  = 0;      // closed segments this half

    function initialize() {
        _hapticTimer = new Timer.Timer();
    }

    // ----------------------------------------------------------
    //  Run control
    // ----------------------------------------------------------

    function isRunning() as Boolean { return _running; }

    function toggle() as Void {
        if (_running) { pause(); } else { start(); }
    }

    function start() as Void {
        if (!_running) {
            _startTick   = System.getTimer();
            _running     = true;
            _hapticTimer.stop();    // the pause reminder, if it was going
            // The first start also sets the running clock going; later
            // starts (after a pause) leave it alone — it never stopped.
            if (!_cuRunning) {
                _cuRunning   = true;
                _cuStartTick = _startTick;
            }
            // Schedule the expiry haptic for the moment we hit 00:00.
            // Already expired (stoppage time) — nothing to schedule.
            var remaining = _intervalMs - _elapsedMs;
            if (remaining > 0) {
                _hapticTimer.start(method(:onExpiry), remaining, false);
            }
        }
    }

    function pause() as Void {
        if (_running) {
            _elapsedMs  += System.getTimer() - _startTick;
            _running     = false;
            // Paused mid-match: drop the expiry one-shot and start the
            // reminder cadence from now on the same Timer.
            _hapticTimer.stop();
            _hapticTimer.start(method(:onPauseReminder), PAUSE_REMIND_MS, true);
        }
    }

    function reset() as Void {
        _running     = false;
        _elapsedMs   = 0;
        _cuRunning   = false;   // the running clock stops and zeroes too
        _hapticTimer.stop();    // no expiry pending, and a reset clock
                                // hasn't started — no nagging either
        // Stoppages belong to the half being reset — drop the open
        // segment, the total and the count.  The Off/On setting survives.
        _stoppageOpen    = false;
        _stoppageTotalMs = 0;
        _stoppageCount   = 0;
    }

    // ----------------------------------------------------------
    //  Configuration
    // ----------------------------------------------------------

    // Changing the interval resets the timer — pick, then kick off.
    function setInterval(minutes as Number, seconds as Number) as Void {
        _intervalMs = (minutes * 60 + seconds) * 1000;
        reset();
    }

    function getIntervalMs() as Number { return _intervalMs; }
    function getIntervalMinPart() as Number { return _intervalMs / 60000; }
    function getIntervalSecPart() as Number { return (_intervalMs / 1000) % 60; }

    // Interval as "MM:SS" for menu labels and half sublabels.
    function formatInterval() as String { return _fmt(_intervalMs / 1000); }

    // 2nd half bases the count-up at the interval instead of 00:00.
    function setSecondHalf(second as Boolean) as Void { _secondHalf = second; }
    function isSecondHalf() as Boolean { return _secondHalf; }

    // ----------------------------------------------------------
    //  Readouts
    // ----------------------------------------------------------

    function getElapsedMs() as Number {
        return _running
            ? _elapsedMs + (System.getTimer() - _startTick)
            : _elapsedMs;
    }

    // Running clock — ms since the first start; 0 until then / after reset.
    function getCountUpMs() as Number {
        return _cuRunning ? (System.getTimer() - _cuStartTick) : 0;
    }
    function isCountUpRunning() as Boolean { return _cuRunning; }

    function isExpired() as Boolean {
        return getElapsedMs() >= _intervalMs;
    }

    // Countdown "MM:SS" — ceiling seconds so 00:00 appears exactly
    // at expiry, and holds there through stoppage time.
    function formatCountdown() as String {
        var rem = _intervalMs - getElapsedMs();
        if (rem < 0) { rem = 0; }
        return _fmt((rem + 999) / 1000);
    }

    // Running-clock count-up "MM:SS" from 00:00 (1st) or the
    // interval (2nd).  Keeps climbing through pauses and past
    // expiry; minutes are uncapped: "93:40" in stoppage.
    function formatCountUp() as String {
        var base = _secondHalf ? _intervalMs : 0;
        return _fmt((base + getCountUpMs()) / 1000);
    }

    hidden function _fmt(totalS as Number) as String {
        var m = totalS / 60;
        var s = totalS % 60;
        return m.format("%02d") + ":" + s.format("%02d");
    }

    // ----------------------------------------------------------
    //  Stoppage timer — the tap-to-start stopwatch
    //
    //  Wholly separate from the countdown and the count-up: nothing
    //  here reads or writes their state, and toggleStoppage() is the
    //  only thing a screen tap ever reaches.  Like the other two it
    //  is a System.getTimer() delta, so it costs no Timer.Timer (the
    //  CIQ timer cap is what crashed the AR2 alert — see CHANGELOG).
    // ----------------------------------------------------------

    function isStoppageEnabled() as Boolean { return _stoppageEnabled; }

    function setStoppageEnabled(enabled as Boolean) as Void {
        // Switching the setting off with a segment open: bank it like a
        // second tap would, otherwise it would keep counting with taps
        // now inert and no way to close it.
        if (!enabled && _stoppageOpen) { _bankStoppage(); }
        _stoppageEnabled = enabled;
    }

    function isStoppageOpen() as Boolean { return _stoppageOpen; }

    // A tap: open a fresh segment, or close the open one and bank it.
    function toggleStoppage() as Void {
        if (_stoppageOpen) {
            _bankStoppage();
        } else {
            _stoppageTick = System.getTimer();
            _stoppageOpen = true;
        }
    }

    // Stoppage so far this half — banked total plus the open segment.
    function getStoppageMs() as Number {
        return _stoppageOpen
            ? _stoppageTotalMs + (System.getTimer() - _stoppageTick)
            : _stoppageTotalMs;
    }

    // Segments so far this half, the open one included — pairs with
    // getStoppageMs() so the menu's "total (n)" agrees with the line.
    function getStoppageCount() as Number {
        return _stoppageOpen ? _stoppageCount + 1 : _stoppageCount;
    }

    // Anything timed this half (an open segment counts from its first
    // instant, so the line appears as "+00:00" on the opening tap).
    function hasStoppage() as Boolean {
        return _stoppageOpen || _stoppageCount > 0;
    }

    // "MM:SS", floor seconds.  The live line prefixes "+".
    function formatStoppage() as String { return _fmt(getStoppageMs() / 1000); }

    hidden function _bankStoppage() as Void {
        _stoppageTotalMs += System.getTimer() - _stoppageTick;
        _stoppageCount   += 1;
        _stoppageOpen     = false;
    }

    // ----------------------------------------------------------
    //  Haptic Timer callbacks — public so method() can reference them
    // ----------------------------------------------------------

    function onExpiry() as Void {
        System.println("MatchTimer: interval expired");
        // The half's regulation time is up: an open stoppage segment
        // closes into the total, so the added-time figure stops here.
        if (_stoppageOpen) { _bankStoppage(); }
        _buzzExpiry();
        WatchUi.requestUpdate();
    }

    // Every PAUSE_REMIND_MS while paused after a start — including with
    // the display off or the settings menu up.
    function onPauseReminder() as Void {
        System.println("MatchTimer: pause reminder");
        _buzzPauseReminder();
    }

    // Paused-clock nudge: two quick taps in ONE vibrate call (no
    // timers) — deliberately the same pattern as BleManager's linked
    // double-tap.  Neither is a page, and a double can't be confused
    // with the triple-tap short press (Alert 3) or the long-press alerts.
    hidden function _buzzPauseReminder() as Void {
        if (!(Attention has :vibrate)) { return; }
        Attention.vibrate([
            new Attention.VibeProfile(100, 120),
            new Attention.VibeProfile(  0, 100),
            new Attention.VibeProfile(100, 120)
        ]);
    }

    // Distinct from the BLE patterns (double-tap, single long,
    // staccato bursts): two long pulses and a longer closer.
    hidden function _buzzExpiry() as Void {
        if (!(Attention has :vibrate)) { return; }
        Attention.vibrate([
            new Attention.VibeProfile(100, 500),
            new Attention.VibeProfile(  0, 250),
            new Attention.VibeProfile(100, 500),
            new Attention.VibeProfile(  0, 250),
            new Attention.VibeProfile(100, 800)
        ]);
    }
}
