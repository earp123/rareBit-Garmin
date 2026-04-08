// ============================================================
// myGarminAppDelegate.mc
//
// Handles physical button presses and screen taps.
//
// SELECT (start button) —
//   IDLE / ERROR / FOUND  →  start scan  (or re-scan)
//   FOUND                 →  connect to the found device
//   (ignored while connecting / subscribing to avoid double-tap)
//
// BACK —
//   SCANNING              →  stop scan
//   SUBSCRIBED / CONNECTED / CONNECTING  →  disconnect / abort
//   otherwise             →  exit app (default behavior)
//
// TAP (touch screen) —
//   FOUND state           →  same as SELECT (connect)
//   otherwise             →  same as SELECT
// ============================================================

import Toybox.Lang;
import Toybox.WatchUi;

class myGarminAppDelegate extends WatchUi.BehaviorDelegate {

    hidden var _ble as BleManager;

    function initialize(ble as BleManager) {
        BehaviorDelegate.initialize();
        _ble = ble;
    }

    // SELECT button (or equivalent "confirm" gesture)
    function onSelect() as Boolean {
        var state = _ble.getState();
        if (state == BLE_FOUND) {
            // A matching device is displayed — connect to it.
            _ble.connectToDevice();
        } else if (state == BLE_IDLE   ||
                   state == BLE_ERROR) {
            // Start (or restart) a BLE scan.
            _ble.startScan();
        }
        // Swallow the event in all cases so the system doesn't also act on it.
        return true;
    }

    // BACK button
    function onBack() as Boolean {
        var state = _ble.getState();
        if (state == BLE_SCANNING) {
            _ble.stopScan();
            return true;  // handled — don't exit the app
        }
        if (state == BLE_CONNECTING  ||
            state == BLE_CONNECTED   ||
            state == BLE_SUBSCRIBED) {
            _ble.disconnect();
            return true;  // handled — stay in app
        }
        if (state == BLE_FOUND) {
            // User changed their mind — go back to idle / re-scan.
            _ble.stopScan();   // clears FOUND state → IDLE
            _ble.startScan();  // immediately re-scan
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

    // Menu button (kept from the original template, now repurposed)
    function onMenu() as Boolean {
        // Re-scan from any state.
        var state = _ble.getState();
        if (state == BLE_SUBSCRIBED ||
            state == BLE_CONNECTED  ||
            state == BLE_CONNECTING) {
            _ble.disconnect();
        }
        _ble.startScan();
        return true;
    }

}
