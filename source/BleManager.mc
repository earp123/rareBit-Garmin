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
// consume it in connectToDevice().
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
const BLE_IDLE        = 0;  // waiting for user to tap SELECT
const BLE_SCANNING    = 1;  // actively scanning
const BLE_FOUND       = 2;  // target device found, waiting for user
const BLE_CONNECTING  = 3;  // pairDevice() called, waiting for link
const BLE_CONNECTED   = 4;  // link up, writing CCCD to enable notify
const BLE_SUBSCRIBED  = 5;  // notifications flowing
const BLE_ERROR       = 6;  // something went wrong (see status string)

// ============================================================
//  NOTIFICATION TYPE CONSTANTS
//  Encoded in the two least-significant bits of the status byte.
// ============================================================
const NOTIFY_LINKED  = 0;   // 0b00 — a tertiary device linked/unlinked
const NOTIFY_ALERT_1 = 1;   // 0b01 — device 1 alert
const NOTIFY_ALERT_2 = 2;   // 0b10 — device 2 alert
const NOTIFY_UNUSED  = 3;   // 0b11 — reserved

// ============================================================
class BleManager extends BluetoothLowEnergy.BleDelegate {

    // Scan-phase state (available while BLE_FOUND)
    hidden var _scanResult  as BluetoothLowEnergy.ScanResult or Null = null;

    // Connection-phase state (available while connected)
    hidden var _device      as BluetoothLowEnergy.Device or Null = null;

    hidden var _state       as Number  = BLE_IDLE;
    hidden var _status      as String  = "Initializing BLE...";
    hidden var _deviceName  as String  = "";
    hidden var _rssi        as Number  = 0;
    hidden var _rxHex       as String  = "--";
    hidden var _rxCount     as Number  = 0;
    hidden var _linked1      as Boolean      = false;  // MSB   — tertiary device 1 linked
    hidden var _linked2      as Boolean      = false;  // MSB-1 — tertiary device 2 linked
    hidden var _notifType    as Number       = -1;     // last NOTIFY_* value, -1 = none yet
    hidden var _notifLocked  as Boolean      = false;  // true during 3 s post-connect gate
    hidden var _notifTimer   as Timer.Timer;           // one-shot to clear the lock
    hidden var _buzzTimer    as Timer.Timer;           // one-shot to chain second buzz burst
    hidden var _buzzTimer2   as Timer.Timer;           // one-shot to chain third buzz burst
    hidden var _svcUuid      as BluetoothLowEnergy.Uuid;
    hidden var _charUuid     as BluetoothLowEnergy.Uuid;

    function initialize() {
        BleDelegate.initialize();
        _notifTimer = new Timer.Timer();
        _buzzTimer  = new Timer.Timer();
        _buzzTimer2 = new Timer.Timer();

        _svcUuid  = BluetoothLowEnergy.stringToUuid(TARGET_SERVICE_UUID_STR);
        _charUuid = BluetoothLowEnergy.stringToUuid(TARGET_CHAR_UUID_STR);

        // Register this instance as the sole BLE event sink.
        BluetoothLowEnergy.setDelegate(self);

        // Declare the GATT profile we intend to access.
        // Must be done before pairDevice() is called.
        _registerProfile();
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
        if (_state == BLE_IDLE   ||
            _state == BLE_ERROR  ||
            _state == BLE_FOUND) {
            _clearSession();
            _state  = BLE_SCANNING;
            _status = "Scanning... (UUID filter active)";
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

    function stopScan() as Void {
        _stopScanInternal();
        if (_state == BLE_SCANNING || _state == BLE_FOUND) {
            _clearSession();
            _state  = BLE_IDLE;
            _status = "Scan stopped. Tap SELECT to retry.";
            WatchUi.requestUpdate();
        }
    }

    // Called when user taps the found-device button.
    // Stop the scan first (kept alive for scan-response name capture),
    // then call pairDevice() with the stored ScanResult.
    function connectToDevice() as Void {
        if (_state == BLE_FOUND && _scanResult != null) {
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
    }

    function disconnect() as Void {
        if (_device != null) {
            try {
                BluetoothLowEnergy.unpairDevice(_device);
            } catch (ex instanceof Lang.Exception) {
                System.println("BLE unpairDevice error: " + ex.getErrorMessage());
            }
        }
        _clearSession();
        _state  = BLE_IDLE;
        _status = "Disconnected. Tap SELECT to scan again.";
        WatchUi.requestUpdate();
    }

    // ----------------------------------------------------------
    //  Internal helpers
    // ----------------------------------------------------------

    hidden function _stopScanInternal() as Void {
        try {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        } catch (ex instanceof Lang.Exception) { /* ignore */ }
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

    // Batch of BLE advertisements received.
    function onScanResults(scanResults as BluetoothLowEnergy.Iterator) as Void {
        if (_state != BLE_SCANNING && _state != BLE_FOUND) { return; }

        var item = scanResults.next();
        while (item != null) {
            var result = item as BluetoothLowEnergy.ScanResult;

            // Update an already-found candidate with fresher data (e.g. scan
            // response packet that arrives after the primary advertisement).
            if (_state == BLE_FOUND && _scanResult != null) {
                if (result.isSameDevice(_scanResult)) {
                    _scanResult = result;
                    var updatedName = _nameFromResult(result);
                    if (updatedName != null) {
                        System.println("BLE: name update -> " + updatedName);
                        _deviceName = updatedName;
                        WatchUi.requestUpdate();
                    }
                }
                item = scanResults.next();
                continue;
            }

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
                    _deviceName = "Relay";
                    _rssi       = result.getRssi();
                    _state      = BLE_FOUND;
                    WatchUi.requestUpdate();
                    break;
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
            _device = device;
            _state  = BLE_CONNECTED;
            // Last-chance name update from the connected Device object,
            // in case neither ad packet carried the name.
            var devName = device.getName();
            if (devName != null) { devName = _stripPrefix(devName); }
            if (devName != null) { _deviceName = devName; }
            _enableNotifications(device);
        } else {
            var wasSub = (_state == BLE_SUBSCRIBED);
            _clearSession();
            _state  = BLE_IDLE;
            _status = wasSub
                ? "Connection lost. Tap SELECT to reconnect."
                : "Pairing failed. Tap SELECT to retry.";
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
            _status      = "Subscribed! Waiting for notifications...";
            _buzzDoubleTap();
        } else {
            _state  = BLE_ERROR;
            _status = "CCCD write failed (status=" + status.toString() + ")";
        }
        WatchUi.requestUpdate();
    }

    // Notification received.
    // Byte layout:
    //   bit 7 (MSB)   — linked status of tertiary device 1 (1=linked)
    //   bit 6         — linked status of tertiary device 2 (1=linked)
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

        // Discard notifications during the 3 s post-subscription window
        // to absorb stacked packets from a wide advertising interval.
        if (_notifLocked) {
            System.println("BLE notify #" + _rxCount + ": suppressed (locked)");
            return;
        }

        // Re-arm the lock so rapid follow-on notifications are suppressed.
        _notifLocked = true;
        _notifTimer.start(method(:_unlockNotif), 5000, false);

        var b      = value[0] & 0xFF;
        _linked1   = ((b >> 7) & 0x01) == 1;
        _linked2   = ((b >> 6) & 0x01) == 1;
        _notifType = b & 0x03;

        System.println("BLE notify #" + _rxCount +
            ": byte=0x" + b.format("%02X") +
            " linked1=" + _linked1 +
            " linked2=" + _linked2 +
            " type="    + _notifType);

        if (_notifType == NOTIFY_LINKED)  { _buzzDoubleTap(); }
        if (_notifType == NOTIFY_ALERT_1) { _buzzAlert1();    }
        if (_notifType == NOTIFY_ALERT_2) { _buzzAlert2();    }

        WatchUi.requestUpdate();
    }

    // Called by _notifTimer after 3 s — opens the notification gate.
    function _unlockNotif() as Void {
        _notifLocked = false;
        System.println("BLE: notification gate open");
    }

    // ----------------------------------------------------------
    //  Haptic feedback
    // ----------------------------------------------------------

    // Double-tap — subscription confirmed, and device-linked events.
    hidden function _buzzDoubleTap() as Void {
        if (!(Attention has :vibrate)) { return; }
        Attention.vibrate([
            new Attention.VibeProfile(100, 120),
            new Attention.VibeProfile(  0, 100),
            new Attention.VibeProfile(100, 120)
        ]);
    }

    // Long single buzz — device 1 alert.
    hidden function _buzzAlert1() as Void {
        if (!(Attention has :vibrate)) { return; }
        Attention.vibrate([
            new Attention.VibeProfile(100, 2000)
        ]);
    }

    // Staccato device 2 alert — two 3-tap bursts chained via _buzzTimer.
    // Burst duration: 3 taps × 160 ms = 480 ms. Gap before burst 2: 300 ms.
    hidden function _buzzAlert2() as Void {
        if (!(Attention has :vibrate)) { return; }
        _buzzTriplet();
        _buzzTimer.start(method(:_buzzTriplet),  480, false);
        _buzzTimer2.start(method(:_buzzTriplet), 960, false);
    }

    // Three-tap burst. Public so method(:) can reference it as a callback.
    function _buzzTriplet() as Void {
        if (!(Attention has :vibrate)) { return; }
        Attention.vibrate([
            new Attention.VibeProfile(100,  80),
            new Attention.VibeProfile(  0,  80),
            new Attention.VibeProfile(100,  80),
            new Attention.VibeProfile(  0,  80),
            new Attention.VibeProfile(100,  80)
        ]);
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
}
