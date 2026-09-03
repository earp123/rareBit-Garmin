// ============================================================
// BleManager.mc
//
// Single BleDelegate that owns all BLE scanning, pairing,
// GATT service/characteristic access, and notification handling.
//
// HOW TO CONFIGURE FOR YOUR DEVICE
// ---------------------------------
// Replace the two UUID strings below with your peripheral's UUIDs.
// Format: "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
//
// PAIRING NOTE: pairDevice() takes the ScanResult object (not a
// Device).  We save it in _scanResult during onScanResults() and
// consume it immediately in _autoConnect() (zero-touch flow).
// ============================================================

import Toybox.Attention;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;
import Toybox.System;

// ============================================================
//  *** CHANGE THESE TWO STRINGS TO MATCH YOUR DEVICE ***
// ============================================================
const TARGET_SERVICE_UUID_STR = "33210001-28d5-4b7b-bad0-7dee1eee1b6d";
const TARGET_CHAR_UUID_STR    = "33210002-28d5-4b7b-bad0-7dee1eee1b6d";

// ============================================================
//  BLE STATE CONSTANTS
// ============================================================
const BLE_IDLE        = 0;  // not scanning (pre-scan or after disconnect)
const BLE_SCANNING    = 1;  // actively scanning; auto-connects on match
                            // 2 was BLE_FOUND (retired: the scan auto-connects)
const BLE_CONNECTING  = 3;  // pairDevice() called, waiting for link
const BLE_CONNECTED   = 4;  // link up, writing CCCD to enable notify
const BLE_SUBSCRIBED  = 5;  // notifications flowing
const BLE_ERROR       = 6;  // something went wrong (see status string)
const BLE_OFFLINE     = 7;  // gave up on BLE — timer-only mode

// Scan gives up (→ BLE_OFFLINE, timer-only) after this long without a
// matching advertisement.  Checked from the view's animation tick.
const SCAN_TIMEOUT_MS = 15000;

// Consecutive pairing failures before giving up (→ BLE_OFFLINE) instead
// of rescanning forever against a relay that won't link.
const MAX_PAIR_FAILS  = 3;

// ============================================================
//  NOTIFICATION TYPE CONSTANTS
//  Encoded in the two least-significant bits of the status byte.
// ============================================================
const NOTIFY_LINKED  = 0;   // 0b00 — an AR device linked/unlinked
const NOTIFY_ALERT_1 = 1;   // 0b01 — AR1 alert
const NOTIFY_ALERT_2 = 2;   // 0b10 — AR2 alert
const NOTIFY_UNUSED  = 3;   // 0b11 — reserved

// How long an alert stays visually active (symbol blink) in ms.
const ALERT_BLINK_MS = 3000;

// ============================================================
class BleManager extends BluetoothLowEnergy.BleDelegate {

    // Scan-phase state (set on UUID match, consumed by _autoConnect)
    hidden var _scanResult  as BluetoothLowEnergy.ScanResult or Null = null;

    // Connection-phase state (available while connected)
    hidden var _device      as BluetoothLowEnergy.Device or Null = null;

    hidden var _state       as Number  = BLE_IDLE;
    hidden var _status      as String  = "Initializing BLE...";
    hidden var _deviceName  as String  = "";
    hidden var _rssi        as Number  = 0;
    hidden var _rxHex       as String  = "--";
    hidden var _rxCount     as Number  = 0;
    hidden var _linked1      as Boolean      = false;  // MSB   — AR1 linked
    hidden var _linked2      as Boolean      = false;  // MSB-1 — AR2 linked
    hidden var _notifType    as Number       = -1;     // last NOTIFY_* value, -1 = none yet
    hidden var _alert1Until  as Number       = 0;      // System.getTimer() deadline for AR1 blink
    hidden var _alert2Until  as Number       = 0;      // System.getTimer() deadline for AR2 blink
    hidden var _notifLocked  as Boolean      = false;  // true during 3 s post-connect gate
    hidden var _notifTimer   as Timer.Timer;           // one-shot to clear the lock
    hidden var _everLive     as Boolean      = false;  // latched on first subscribe/give-up
    hidden var _scanDeadline as Number       = 0;      // getTimer() ms when the scan gives up
    hidden var _pairFails    as Number       = 0;      // consecutive pairing failures
    hidden var _svcUuid      as BluetoothLowEnergy.Uuid;
    hidden var _charUuid     as BluetoothLowEnergy.Uuid;

    function initialize() {
        BleDelegate.initialize();
        _notifTimer = new Timer.Timer();

        _svcUuid  = BluetoothLowEnergy.stringToUuid(TARGET_SERVICE_UUID_STR);
        _charUuid = BluetoothLowEnergy.stringToUuid(TARGET_CHAR_UUID_STR);

        // Register this instance as the sole BLE event sink.
        BluetoothLowEnergy.setDelegate(self);

        // Declare the GATT profile we intend to access.
        // Must be done before pairDevice() is called.
        _registerProfile();

        if (SIM_TIMER_TEST) {
            // Simulator UI test — skip the BLE flow and boot straight
            // into the live match-timer screen, both ARs linked.
            _state    = BLE_SUBSCRIBED;
            _status   = "SIM TEST MODE";
            _everLive = true;   // keep the live latch consistent in the sim
            _linked1  = true;
            _linked2  = true;
        }
    }

    hidden function _registerProfile() as Void {
        try {
            BluetoothLowEnergy.registerProfile({
                :uuid => _svcUuid,
                :characteristics => [{
                    :uuid => _charUuid,
                    :descriptors => [BluetoothLowEnergy.cccdUuid()]
                }]
            });
            System.println("BLE: registerProfile sent");
            _status = "Profile sent. Tap SELECT to scan.";
        } catch (ex instanceof Lang.Exception) {
            _state  = BLE_ERROR;
            _status = "Profile reg failed!";
            System.println("BLE registerProfile error: " + ex.getErrorMessage());
        }
    }

    // ----------------------------------------------------------
    //  Public control methods
    // ----------------------------------------------------------

    function startScan() as Void {
        if (_state == BLE_IDLE    ||
            _state == BLE_ERROR   ||
            _state == BLE_OFFLINE) {
            if (_state == BLE_OFFLINE) {
                // User-initiated rescan from timer-only mode: the
                // pairing-failure count from the last attempt is stale.
                _pairFails = 0;
            }
            // An ERROR state (e.g. CCCD write failed) can still hold a
            // live GATT link.  Release it before scanning — a connected
            // relay stops advertising, so a rescan would never see it.
            _unpairIfHeld();
            _clearSession();
            _state        = BLE_SCANNING;
            _status       = "Scanning... (UUID filter active)";
            _scanDeadline = System.getTimer() + SCAN_TIMEOUT_MS;
            System.println("BLE: start scan");
            try {
                BluetoothLowEnergy.setScanState(
                    BluetoothLowEnergy.SCAN_STATE_SCANNING);
            } catch (ex instanceof Lang.Exception) {
                _state  = BLE_ERROR;
                _status = "Scan start failed!";
                System.println("BLE setScanState error: " + ex.getErrorMessage());
            }
            WatchUi.requestUpdate();
        }
    }

    // The app is "live" (showing the match timer) once we've either
    // subscribed or given up on BLE.  Latched — BLE drops and background
    // rescans never pull the UI off the timer screen.
    function isLive() as Boolean {
        return _everLive || _state == BLE_SUBSCRIBED;
    }

    // Called from the view's tick while scanning: give up and fall back
    // to timer-only mode once the scan deadline passes.
    function checkScanTimeout() as Void {
        // Delta compare, not "getTimer() > deadline" — see _alertOpen().
        if (_state == BLE_SCANNING &&
            (System.getTimer() - _scanDeadline) > 0) {
            System.println("BLE: scan timeout — timer-only mode");
            _stopScanInternal();
            _clearSession();
            _state    = BLE_OFFLINE;
            _everLive = true;
            _status   = "No relay found — timer only";
            WatchUi.requestUpdate();
        }
    }

    // User skipped the connect phase (BACK during scan/connect) — quiesce
    // BLE and go straight to the timer.
    function skipToTimer() as Void {
        teardown();
        _state    = BLE_OFFLINE;
        _everLive = true;
        _status   = "Timer only (skipped scan)";
        WatchUi.requestUpdate();
    }

    // Auto-connect to a freshly matched advertisement: stop the scan and
    // pair immediately — no confirmation press.
    hidden function _autoConnect() as Void {
        _stopScanInternal();
        _state  = BLE_CONNECTING;
        _status = "Pairing with " + _deviceName + "...";
        WatchUi.requestUpdate();
        System.println("BLE: pairDevice " + _deviceName);
        try {
            BluetoothLowEnergy.pairDevice(_scanResult);
        } catch (ex instanceof Lang.Exception) {
            _state  = BLE_ERROR;
            _status = "Pair failed: " + ex.getErrorMessage();
            System.println("BLE pairDevice error: " + ex.getErrorMessage());
            WatchUi.requestUpdate();
        }
    }

    function disconnect() as Void {
        teardown();
        if (_everLive) {
            _state = BLE_OFFLINE;
            _status = "Disconnected — timer only";
        } else {
            _status = "Disconnected. Tap SELECT to scan again.";
        }
        WatchUi.requestUpdate();
    }

    // Full teardown — stop any scan, release any GATT connection, and
    // clear all session state.  Safe to call from any state; also used
    // on app exit so nothing is left running or paired behind us.
    function teardown() as Void {
        _stopScanInternal();
        _unpairIfHeld();
        _clearSession();
        _state = BLE_IDLE;
    }

    // ----------------------------------------------------------
    //  Internal helpers
    // ----------------------------------------------------------

    hidden function _stopScanInternal() as Void {
        try {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        } catch (ex instanceof Lang.Exception) { /* ignore */ }
    }

    // Release the GATT link if we hold one.  The stack then echoes
    // onConnectedStateChanged(DISCONNECTED), which that handler
    // recognises as self-initiated and ignores.
    hidden function _unpairIfHeld() as Void {
        if (_device != null) {
            try {
                BluetoothLowEnergy.unpairDevice(_device);
            } catch (ex instanceof Lang.Exception) {
                System.println("BLE unpairDevice error: " + ex.getErrorMessage());
            }
        }
    }

    hidden function _clearSession() as Void {
        _scanResult = null;
        _device     = null;
        _deviceName = "";
        _rssi       = 0;
        _rxHex      = "--";
        _rxCount      = 0;
        _linked1      = false;
        _linked2      = false;
        _notifType    = -1;
        _alert1Until  = 0;
        _alert2Until  = 0;
        _notifLocked  = false;
        _notifTimer.stop();
    }

    // After connecting: find our characteristic and write 0x0001 to its
    // CCCD to enable BLE notifications.
    hidden function _enableNotifications(device as BluetoothLowEnergy.Device) as Void {
        _status = "Connected! Enabling notifications...";
        WatchUi.requestUpdate();
        try {
            var svc = device.getService(_svcUuid);
            if (svc == null) {
                _state  = BLE_ERROR;
                _status = "Service UUID not found on device!";
                System.println("BLE: service not found");
                WatchUi.requestUpdate();
                return;
            }
            var chr = svc.getCharacteristic(_charUuid);
            if (chr == null) {
                _state  = BLE_ERROR;
                _status = "Notify char not found!";
                System.println("BLE: char not found");
                WatchUi.requestUpdate();
                return;
            }
            var cccd = chr.getDescriptor(BluetoothLowEnergy.cccdUuid());
            if (cccd == null) {
                _state  = BLE_ERROR;
                _status = "CCCD descriptor missing!";
                System.println("BLE: CCCD not found");
                WatchUi.requestUpdate();
                return;
            }
            // 0x0001 = enable notifications  |  0x0002 = enable indications
            cccd.requestWrite([0x01, 0x00]b);
            System.println("BLE: CCCD write sent — notifications requested");
            _status = "Enabling notifications...";
        } catch (ex instanceof Lang.Exception) {
            _state  = BLE_ERROR;
            _status = "GATT error: " + ex.getErrorMessage();
            System.println("BLE _enableNotifications error: " + ex.getErrorMessage());
        }
        WatchUi.requestUpdate();
    }

    // ----------------------------------------------------------
    //  BleDelegate callbacks — exact signatures from SDK docs
    // ----------------------------------------------------------

    // Profile registration result.
    // status is BluetoothLowEnergy.Status (not Number).
    function onProfileRegister(
        uuid   as BluetoothLowEnergy.Uuid,
        status as BluetoothLowEnergy.Status) as Void
    {
        System.println("BLE: onProfileRegister status=" + status);
        if (SIM_TIMER_TEST) { return; }  // sim test — stay in forced SUBSCRIBED state
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            _status = "Profile OK. Tap SELECT to start scanning.";
        } else {
            _state  = BLE_ERROR;
            _status = "Profile reg failed (status=" + status.toString() + ")";
        }
        WatchUi.requestUpdate();
    }

    // Scan state changed; status is BluetoothLowEnergy.Status.
    function onScanStateChange(
        scanState as BluetoothLowEnergy.ScanState,
        status    as BluetoothLowEnergy.Status) as Void
    {
        System.println("BLE: scan state=" + scanState + " status=" + status);
    }

    // Batch of BLE advertisements received.  First result advertising
    // our service UUID wins — connect to it immediately (we don't expect
    // more than one rareBit relay in range).
    function onScanResults(scanResults as BluetoothLowEnergy.Iterator) as Void {
        if (_state != BLE_SCANNING) { return; }

        var item = scanResults.next();
        while (item != null) {
            var result = item as BluetoothLowEnergy.ScanResult;

            // Check every result for our service UUID.
            var uuidIter = result.getServiceUuids();
            var uuidObj  = uuidIter.next();
            while (uuidObj != null) {
                var uuid = uuidObj as BluetoothLowEnergy.Uuid;
                if (uuid.equals(_svcUuid)) {
                    var name = _nameFromResult(result);
                    System.println("BLE: UUID match — getDeviceName=" +
                        result.getDeviceName() + " parsed=" + name +
                        " RSSI=" + result.getRssi());
                    _scanResult = result;
                    _deviceName = (name != null) ? name : "Relay";
                    _rssi       = result.getRssi();
                    _autoConnect();
                    return;
                }
                uuidObj = uuidIter.next();
            }

            item = scanResults.next();
        }
    }

    // Resolve the device name from a ScanResult.
    // 1. Try getDeviceName() — works when the name is in the same packet.
    // 2. Fall back to parsing raw advertisement bytes for AD types 0x08/0x09
    //    (Shortened / Complete Local Name) in case the CIQ stack doesn't
    //    surface the name via getDeviceName() for this device.
    hidden function _nameFromResult(result as BluetoothLowEnergy.ScanResult) as String or Null {
        // --- path 1: standard API ---
        var apiName = result.getDeviceName();
        if (apiName != null && apiName.length() > 0) {
            return _stripPrefix(apiName);
        }

        // --- path 2: manual raw AD structure parse ---
        var raw = result.getRawData();
        if (raw != null) {
            var i = 0;
            while (i < raw.size()) {
                var adLen  = raw[i] & 0xFF;
                if (adLen == 0) { break; }
                if (i + adLen >= raw.size()) { break; }
                var adType = raw[i + 1] & 0xFF;
                // 0x08 = Shortened Local Name, 0x09 = Complete Local Name
                if (adType == 0x08 || adType == 0x09) {
                    var nameBytes = raw.slice(i + 2, i + 1 + adLen);
                    var parsed = _bytesToString(nameBytes);
                    System.println("BLE: raw AD name (" + adType.format("%02X") + ") = " + parsed);
                    return _stripPrefix(parsed);
                }
                i += 1 + adLen;
            }
        }

        return null;
    }

    // Convert a byte array of ASCII/UTF-8 characters to a String.
    hidden function _bytesToString(bytes as ByteArray) as String {
        var s = "";
        for (var i = 0; i < bytes.size(); i++) {
            var b = bytes[i] & 0xFF;
            if (b == 0) { break; }          // null terminator
            s = s + b.format("%c");
        }
        return s;
    }

    // Strip leading "rareBit " brand prefix.
    hidden function _stripPrefix(name as String) as String {
        var prefix = "rareBit ";
        if (name.length() > prefix.length() &&
            name.substring(0, prefix.length()).equals(prefix)) {
            return name.substring(prefix.length(), name.length());
        }
        return name;
    }

    // Connection state changed after pairDevice() or unpairDevice().
    function onConnectedStateChanged(
        device as BluetoothLowEnergy.Device,
        state  as BluetoothLowEnergy.ConnectionState) as Void
    {
        System.println("BLE: connState=" + state);
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            _device     = device;
            _scanResult = null;   // consumed by pairDevice — don't hold it stale
            _state      = BLE_CONNECTED;
            // Last-chance name update from the connected Device object,
            // in case neither ad packet carried the name.
            var devName = device.getName();
            if (devName != null) { devName = _stripPrefix(devName); }
            if (devName != null) { _deviceName = devName; }
            _enableNotifications(device);
        } else {
            var wasSub = (_state == BLE_SUBSCRIBED);
            // Only CONNECTING / CONNECTED / SUBSCRIBED can lose a link we
            // still want.  Any other state means this disconnect is the
            // echo of our own unpairDevice() (menu Disconnect, BACK-to-
            // skip, pre-scan release) — clear and stay put.  Without this
            // guard a menu Disconnect counted as a pairing failure and
            // started an auto-rescan that re-paired seconds later.
            var ours = !wasSub &&
                       _state != BLE_CONNECTING &&
                       _state != BLE_CONNECTED;
            _clearSession();
            if (ours) {
                System.println("BLE: disconnect echo in state " + _state + " — ignored");
                return;
            }
            if (!wasSub) { _pairFails++; }
            if (!wasSub && _pairFails >= MAX_PAIR_FAILS) {
                // Relay advertises but won't link — stop burning battery.
                _state    = BLE_OFFLINE;
                _everLive = true;
                _status   = "Relay unreachable — timer only";
                System.println("BLE: " + _pairFails + " pair failures — timer-only mode");
            } else {
                // Auto-rescan: reconnect when the relay reappears.  If the
                // live screen is up it stays up (isLive is latched); the
                // scan-deadline fallback still applies.
                _state = BLE_IDLE;
                System.println(wasSub
                    ? "BLE: connection lost — rescanning"
                    : "BLE: pairing failed — rescanning");
                startScan();
            }
            WatchUi.requestUpdate();
        }
    }

    // CCCD write complete — if successful, notifications are active.
    // Signature: 2 params (descriptor, status).  No device parameter.
    function onDescriptorWrite(
        descriptor as BluetoothLowEnergy.Descriptor,
        status     as BluetoothLowEnergy.Status) as Void
    {
        System.println("BLE: descriptor write status=" + status);
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            _state       = BLE_SUBSCRIBED;
            _everLive    = true;
            _pairFails   = 0;
            _status      = "Subscribed! Waiting for notifications...";
            // Close the notification gate for 3 s to absorb stale packets
            // stacked up during a wide advertising interval.
            _notifLocked = true;
            _notifTimer.start(method(:_unlockNotif), 3000, false);
            _buzzDoubleTap();
        } else {
            _state  = BLE_ERROR;
            _status = "CCCD write failed (status=" + status.toString() + ")";
        }
        WatchUi.requestUpdate();
    }

    // Notification received.
    // Byte layout:
    //   bit 7 (MSB)   — linked status of AR1 (1=linked)
    //   bit 6         — linked status of AR2 (1=linked)
    //   bits 5-2      — reserved
    //   bits 1-0 (LSB)— notification type (NOTIFY_* constants)
    function onCharacteristicChanged(
        characteristic as BluetoothLowEnergy.Characteristic,
        value          as ByteArray) as Void
    {
        _rxCount++;
        if (value.size() < 1) {
            System.println("BLE notify #" + _rxCount + ": empty payload");
            WatchUi.requestUpdate();
            return;
        }

        var b      = value[0] & 0xFF;
        _linked1   = ((b >> 7) & 0x01) == 1;
        _linked2   = ((b >> 6) & 0x01) == 1;

        // During the 3 s post-subscription gate, absorb stacked stale
        // packets: keep the link-status bits fresh but skip the alert
        // label and buzz.
        if (_notifLocked) {
            System.println("BLE notify #" + _rxCount + ": gated (linked bits updated)");
            WatchUi.requestUpdate();
            return;
        }

        _notifType = b & 0x03;

        System.println("BLE notify #" + _rxCount +
            ": byte=0x" + b.format("%02X") +
            " linked1=" + _linked1 +
            " linked2=" + _linked2 +
            " type="    + _notifType);

        if (_notifType == NOTIFY_LINKED)  { _buzzDoubleTap(); }
        if (_notifType == NOTIFY_ALERT_1) {
            _alert1Until = System.getTimer() + ALERT_BLINK_MS;
            _buzzAlert1();
        }
        if (_notifType == NOTIFY_ALERT_2) {
            _alert2Until = System.getTimer() + ALERT_BLINK_MS;
            _buzzAlert2();
        }

        WatchUi.requestUpdate();
    }

    // Called by _notifTimer 3 s after subscribing — opens the notification gate.
    function _unlockNotif() as Void {
        _notifLocked = false;
        System.println("BLE: notification gate open");
    }

    // ----------------------------------------------------------
    //  Haptic feedback
    // ----------------------------------------------------------

    // Double-tap — subscription confirmed, and AR-linked events.
    hidden function _buzzDoubleTap() as Void {
        if (!(Attention has :vibrate)) { return; }
        Attention.vibrate([
            new Attention.VibeProfile(100, 120),
            new Attention.VibeProfile(  0, 100),
            new Attention.VibeProfile(100, 120)
        ]);
    }

    // Long single buzz — AR1 alert.
    hidden function _buzzAlert1() as Void {
        if (!(Attention has :vibrate)) { return; }
        Attention.vibrate([
            new Attention.VibeProfile(100, 2000)
        ]);
    }

    // AR2 alert — four long buzzes with short gaps (~2.5 s total),
    // encoded as a SINGLE vibrate call.  The old version chained
    // bursts through two one-shot Timers; with the match timer
    // running (view tick + expiry one-shot already holding slots)
    // that blew the CIQ concurrent-timer limit and crashed.  Zero
    // timers this way.  Distinct from AR1's single continuous buzz.
    hidden function _buzzAlert2() as Void {
        if (!(Attention has :vibrate)) { return; }
        Attention.vibrate([
            new Attention.VibeProfile(100, 500),
            new Attention.VibeProfile(  0, 150),
            new Attention.VibeProfile(100, 500),
            new Attention.VibeProfile(  0, 150),
            new Attention.VibeProfile(100, 500),
            new Attention.VibeProfile(  0, 150),
            new Attention.VibeProfile(100, 500)
        ]);
    }

    // ----------------------------------------------------------
    //  Sim-test hook — open an AR's alert-flash window without BLE
    //  traffic (wired to menu items only in the SIM_TIMER_TEST build).
    // ----------------------------------------------------------
    function simulateAlert(arNum as Number) as Void {
        var until = System.getTimer() + ALERT_BLINK_MS;
        if (arNum == 1) { _alert1Until = until; }
        else            { _alert2Until = until; }
        WatchUi.requestUpdate();
    }

    // ----------------------------------------------------------
    //  Getters for the View
    // ----------------------------------------------------------
    function getState()      as Number  { return _state;      }
    function getStatus()     as String  { return _status;     }
    function getDeviceName() as String  { return _deviceName; }
    function getRssi()       as Number  { return _rssi;       }
    function getRxHex()      as String  { return _rxHex;      }
    function getRxCount()    as Number  { return _rxCount;    }
    function getLinked1()    as Boolean { return _linked1;    }
    function getLinked2()    as Boolean { return _linked2;    }
    function getNotifType()  as Number  { return _notifType;  }

    // True while the AR's alert blink window (ALERT_BLINK_MS) is open.
    function isAlerting1()   as Boolean { return _alertOpen(_alert1Until); }
    function isAlerting2()   as Boolean { return _alertOpen(_alert2Until); }

    // Window test as a DELTA, never "getTimer() < deadline": System.getTimer()
    // is a signed 32-bit ms counter that rolls negative ~25 days after a
    // reboot, and with the deadlines initialised to 0 the absolute compare
    // read as "alerting" for both ARs until their first real page (seen
    // on-watch 2026-09-02).  Subtraction wraps, so this holds across the
    // rollover.
    hidden function _alertOpen(deadline as Number) as Boolean {
        var remaining = deadline - System.getTimer();
        return remaining > 0 && remaining <= ALERT_BLINK_MS;
    }
}
