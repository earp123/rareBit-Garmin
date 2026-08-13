// ============================================================
// MatchTimer.mc
//
// Match / interval timer for sports officials.
//
// Primary display is a COUNTDOWN from the selected interval
// (default 45 min).  A synchronized COUNT-UP runs off the same
// elapsed clock, based at 00:00 (1st half) or at the interval
// (2nd half — e.g. counts up from 45:00 with 45-min intervals).
//
// start/pause preserves elapsed time; reset() returns to the
// full interval, paused.  Elapsed time is derived from
// System.getTimer() deltas, so no periodic callback is needed
// to keep time — the view only ticks to refresh the display.
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

class MatchTimer {

    hidden var _running     as Boolean = false;
    hidden var _elapsedMs   as Number  = 0;   // accumulated up to last pause
    hidden var _startTick   as Number  = 0;   // System.getTimer() at last start
    hidden var _intervalMs  as Number  = DEFAULT_INTERVAL_MIN * 60 * 1000;
    hidden var _secondHalf  as Boolean = false;  // count-up base = interval when true
    hidden var _expiryTimer as Timer.Timer;      // one-shot → haptic at 00:00

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
            _startTick = System.getTimer();
            _running   = true;
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
            _elapsedMs += System.getTimer() - _startTick;
            _running    = false;
            _expiryTimer.stop();
        }
    }

    function reset() as Void {
        _running   = false;
        _elapsedMs = 0;
        _expiryTimer.stop();
    }

    // ----------------------------------------------------------
    //  Configuration
    // ----------------------------------------------------------

    // Changing the interval resets the timer — pick, then kick off.
    function setIntervalMin(minutes as Number) as Void {
        _intervalMs = minutes * 60 * 1000;
        reset();
    }

    function getIntervalMin() as Number { return _intervalMs / 60000; }

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

    // Synchronized count-up "MM:SS" from 00:00 (1st) or the
    // interval (2nd).  Minutes are uncapped: "93:40" in stoppage.
    function formatCountUp() as String {
        var base = _secondHalf ? _intervalMs : 0;
        return _fmt((base + getElapsedMs()) / 1000);
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
