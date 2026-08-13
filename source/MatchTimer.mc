// ============================================================
// MatchTimer.mc
//
// Match / interval timer for sports officials.
//
// Counts up from 00:00.  start/pause preserves elapsed time;
// reset() returns to 00:00 paused.  Elapsed time is derived from
// System.getTimer() deltas, so no periodic callback is needed to
// keep time — the view only ticks to refresh the display.
//
// Owned by the App (like BleManager) so it survives BLE drops
// and reconnects without losing match time.
// ============================================================

import Toybox.Lang;
import Toybox.System;

class MatchTimer {

    hidden var _running   as Boolean = false;
    hidden var _elapsedMs as Number  = 0;   // accumulated up to last pause
    hidden var _startTick as Number  = 0;   // System.getTimer() at last start

    function isRunning() as Boolean { return _running; }

    function toggle() as Void {
        if (_running) { pause(); } else { start(); }
    }

    function start() as Void {
        if (!_running) {
            _startTick = System.getTimer();
            _running   = true;
        }
    }

    function pause() as Void {
        if (_running) {
            _elapsedMs += System.getTimer() - _startTick;
            _running    = false;
        }
    }

    function reset() as Void {
        _running   = false;
        _elapsedMs = 0;
    }

    function getElapsedMs() as Number {
        return _running
            ? _elapsedMs + (System.getTimer() - _startTick)
            : _elapsedMs;
    }

    // "MM:SS" — minutes are uncapped, so 75 min shows as "75:00".
    function format() as String {
        var totalS = getElapsedMs() / 1000;
        var m = totalS / 60;
        var s = totalS % 60;
        return m.format("%02d") + ":" + s.format("%02d");
    }
}
