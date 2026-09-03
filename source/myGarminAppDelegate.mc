// ============================================================
// myGarminAppDelegate.mc
//
// Handles physical button presses and screen touches.
//
// The app auto-scans and auto-connects on launch; once "live" (timer
// screen up — subscribed, or BLE given up) inputs drive the timer and
// BLE events never change the routing.
//
// Raw InputDelegate, NOT BehaviorDelegate: a BehaviorDelegate folds a
// touchscreen tap into the select behavior before onTap can veto it,
// so a sleeve or raindrop would pause the match.  At this level keys
// and taps arrive separately, so the live screen is SELECT-button-only.
//
// SELECT (button) —
//   live                  →  start / pause the match timer
//   IDLE / ERROR          →  start (or retry) a scan
//   (ignored while scanning / connecting — it's all automatic)
//
// TAP —
//   live                  →  ignored (stray-touch guard)
//   otherwise             →  same as SELECT
//
// BACK —
//   live                  →  open the settings menu (interval / half /
//                            reset / disconnect-or-rescan / exit)
//   SCANNING / CONNECTING / CONNECTED (pre-live)
//                         →  skip BLE, go straight to the timer
//   otherwise             →  exit app (default behavior)
//
// MENU key / touch-and-hold —
//   live                  →  open the settings menu (same as BACK)
//   otherwise             →  restart the scan
// ============================================================

import Toybox.Lang;
import Toybox.WatchUi;

class myGarminAppDelegate extends WatchUi.InputDelegate {

    hidden var _ble        as BleManager;
    hidden var _matchTimer as MatchTimer;

    function initialize(ble as BleManager, matchTimer as MatchTimer) {
        InputDelegate.initialize();
        _ble        = ble;
        _matchTimer = matchTimer;
    }

    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        var k = keyEvent.getKey();
        if (k == WatchUi.KEY_ENTER || k == WatchUi.KEY_START) { return _select(); }
        if (k == WatchUi.KEY_ESC)  { return _back(); }
        if (k == WatchUi.KEY_MENU) { return _menu(); }
        return false;
    }

    // Touch-screen tap — never touches the clock on the live screen.
    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        if (_ble.isLive()) { return true; }
        return _select();
    }

    // Touch-and-hold stands in for the MENU key on touch devices.
    function onHold(clickEvent as WatchUi.ClickEvent) as Boolean {
        return _menu();
    }

    hidden function _select() as Boolean {
        if (_ble.isLive()) {
            // Live screen — SELECT drives the match timer.
            _matchTimer.toggle();
            WatchUi.requestUpdate();
            return true;
        }
        var state = _ble.getState();
        if (state == BLE_IDLE || state == BLE_ERROR) {
            // Manual retry from a stopped/errored pre-live state.
            _ble.startScan();
        }
        // Swallow in all cases so the system doesn't also act on it.
        return true;
    }

    hidden function _back() as Boolean {
        if (_ble.isLive()) {
            // Live screen — BACK opens the settings menu.
            pushMatchMenu(_matchTimer, _ble);
            return true;
        }
        var state = _ble.getState();
        if (state == BLE_SCANNING   ||
            state == BLE_CONNECTING ||
            state == BLE_CONNECTED) {
            // Don't make the user wait out the scan — straight to the timer.
            _ble.skipToTimer();
            return true;
        }
        // IDLE / ERROR — let the system handle BACK (exits app).
        return false;
    }

    hidden function _menu() as Boolean {
        if (_ble.isLive()) {
            // Live screen — MENU opens the settings menu (same as BACK).
            pushMatchMenu(_matchTimer, _ble);
            return true;
        }
        // Pre-live — restart the scan.
        var state = _ble.getState();
        if (state == BLE_CONNECTED  ||
            state == BLE_CONNECTING) {
            _ble.disconnect();
        }
        _ble.startScan();
        return true;
    }

}
