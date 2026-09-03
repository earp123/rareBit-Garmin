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
// while the count-up keeps going (stoppage time).
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
// gentle reminder this often (polled from the view's idle tick).
const PAUSE_REMIND_MS = 20000;

class MatchTimer {

    hidden var _running     as Boolean = false;  // countdown (playing clock) running
    hidden var _elapsedMs   as Number  = 0;      // countdown ms accumulated to last pause
    hidden var _startTick   as Number  = 0;      // System.getTimer() at last countdown start
    hidden var _cuRunning   as Boolean = false;  // count-up (running clock) started
    hidden var _cuStartTick as Number  = 0;      // System.getTimer() at the first start
    hidden var _intervalMs  as Number  = DEFAULT_INTERVAL_MIN * 60 * 1000;
    hidden var _secondHalf  as Boolean = false;  // count-up base = interval when true
    hidden var _expiryTimer as Timer.Timer;      // one-shot → haptic at 00:00
    hidden var _remindArmed as Boolean = false;  // paused after a start — nag
    hidden var _remindTick  as Number  = 0;      // getTimer() base for the nag

    function initialize() {
        _expiryTimer = new Timer.Timer();
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
            _remindArmed = false;
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
                _expiryTimer.start(method(:onExpiry), remaining, false);
            }
        }
    }

    function pause() as Void {
        if (_running) {
            _elapsedMs  += System.getTimer() - _startTick;
            _running     = false;
            _expiryTimer.stop();
            // Paused mid-match: start the reminder cadence from now.
            _remindArmed = true;
            _remindTick  = System.getTimer();
        }
    }

    function reset() as Void {
        _running     = false;
        _elapsedMs   = 0;
        _cuRunning   = false;   // the running clock stops and zeroes too
        _remindArmed = false;   // a reset timer hasn't started — no nagging
        _expiryTimer.stop();
    }

    // Pause reminder — polled from the view's tick rather than run off
    // a Timer of its own, keeping the app's timer count down.  Delta
    // compare: System.getTimer() rolls negative ~25 days after boot.
    function pollPauseReminder() as Void {
        if (!_remindArmed) { return; }
        if (System.getTimer() - _remindTick >= PAUSE_REMIND_MS) {
            _remindTick = System.getTimer();
            _buzzPauseReminder();
        }
    }

    // ----------------------------------------------------------
    //  Configuration
    // ----------------------------------------------------------

    // Changing the interval resets the timer — pick, then kick off.
    function setInterval(minutes as Number, seconds as Number) as Void {
        _intervalMs = (minutes * 60 + seconds) * 1000;
        reset();
    }

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
    //  Expiry — public so method(:onExpiry) can reference it
    // ----------------------------------------------------------

    function onExpiry() as Void {
        System.println("MatchTimer: interval expired");
        _buzzExpiry();
        WatchUi.requestUpdate();
    }

    // Paused-clock nudge: a single short tap — unmistakably not an
    // alert, just "your clock is stopped".
    hidden function _buzzPauseReminder() as Void {
        if (!(Attention has :vibrate)) { return; }
        Attention.vibrate([
            new Attention.VibeProfile(100, 80)
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
