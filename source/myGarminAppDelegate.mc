// ============================================================
// myGarminAppDelegate.mc
//
// Handles physical button presses and screen taps.
//
// The app auto-scans and auto-connects on launch; once "live" (timer
// screen up — subscribed, or BLE given up) inputs drive the timer and
// BLE events never change the routing.
//
// SELECT / TAP —
//   live                  →  start / pause the match timer
//   IDLE / ERROR          →  start (or retry) a scan
//   (ignored while scanning / connecting — it's all automatic)
//
// BACK —
//   live                  →  open the settings menu (interval / half /
//                            reset / disconnect-or-rescan)
//   SCANNING / CONNECTING / CONNECTED (pre-live)
//                         →  skip BLE, go straight to the timer
//   otherwise             →  exit app (default behavior)
//
// MENU —
//   live                  →  open the settings menu (same as BACK)
//   otherwise             →  restart the scan
// ============================================================

import Toybox.Lang;
import Toybox.WatchUi;

class myGarminAppDelegate extends WatchUi.BehaviorDelegate {

    hidden var _ble        as BleManager;
    hidden var _matchTimer as MatchTimer;

    function initialize(ble as BleManager, matchTimer as MatchTimer) {
        BehaviorDelegate.initialize();
        _ble        = ble;
        _matchTimer = matchTimer;
    }

    // SELECT button (or equivalent "confirm" gesture)
    function onSelect() as Boolean {
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
        // Swallow the event in all cases so the system doesn't also act on it.
        return true;
    }

    // BACK button
    function onBack() as Boolean {
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

    // Touch-screen tap
    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        // Treat a tap anywhere as a SELECT in most states.
        return onSelect();
    }

    // Menu button
    function onMenu() as Boolean {
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
