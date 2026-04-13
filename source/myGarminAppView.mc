// ============================================================
// myGarminAppView.mc
//
// Shape-aware layout — detects round vs rectangular screen at
// init and computes a safe vertical band from the inscribed
// square (round) or a small fixed margin (rectangular).
//
// Safe zone: roughly 15% inset from top/bottom on round screens
//   (= half of (diameter - inscribed-square-side), i.e. D*(1-1/√2)/2)
//
// Vertical stack within the safe zone:
//   14%  colored dot   — state indicator only, no text
//   50%  main area     — card or spinner
//   88%  bottom text   — single short line, very muted
// ============================================================

import Toybox.BluetoothLowEnergy;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// ── Colors ───────────────────────────────────────────────────
const C_BG          = Graphics.COLOR_BLACK;
const C_CARD_FILL   = 0x111111;
const C_CARD_BORDER = Graphics.COLOR_WHITE;
const C_TEXT_PRI    = Graphics.COLOR_WHITE;
const C_TEXT_SEC    = 0x888888;
const C_HINT        = 0x444444;

const C_ACC_IDLE    = 0x555555;
const C_ACC_ACTIVE  = 0xFFAA00;  // amber — scanning / connecting
const C_ACC_FOUND   = 0xFFFFFF;  // white — device waiting
const C_ACC_LIVE    = 0x00CC66;  // green — data flowing
const C_ACC_ERROR   = 0xCC2200;  // red

// ── Geometry ─────────────────────────────────────────────────
const CARD_PAD    = 14;   // px padding inside card
const CARD_RADIUS = 10;   // corner radius px
const CARD_W_PCT  = 0.72; // card width as fraction of screen width
const DOT_R       = 5;    // state dot radius px
const SPINNER_PW  = 4;    // spinner arc pen width px

class myGarminAppView extends WatchUi.View {

    hidden var _ble          as BleManager;
    hidden var _timer        as Timer.Timer;
    hidden var _timerRunning as Boolean = false;
    hidden var _animFrame    as Number  = 0;   // 0-5
    hidden var _isRound      as Boolean = false;
    hidden var _timerPushed  as Boolean = false;
    hidden var _menuShown    as Boolean = false;

    function initialize(ble as BleManager) {
        View.initialize();
        _ble   = ble;
        _timer = new Timer.Timer();
        // Detect screen shape once — doesn't change at runtime
        var shape = System.getDeviceSettings().screenShape;
        _isRound = (shape == System.SCREEN_SHAPE_ROUND ||
                    shape == System.SCREEN_SHAPE_SEMI_ROUND);
    }

    function onLayout(dc as Graphics.Dc) as Void { }

    function onShow() as Void {
        _menuShown = false;
        var state = _ble.getState();
        if (state == BLE_IDLE || state == BLE_ERROR) {
            _ble.startScan();
        }
        _syncTimer();
        WatchUi.requestUpdate();
    }

    function onHide() as Void {
        _timer.stop();
        _timerRunning = false;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var state = _ble.getState();

        // ── Navigate to timer view on first successful subscription ──
        if (state == BLE_SUBSCRIBED && !_timerPushed) {
            _timerPushed = true;
            WatchUi.pushView(new TimerView(_ble), new TimerDelegate(), WatchUi.SLIDE_UP);
            return;
        }
        if (state != BLE_SUBSCRIBED) {
            _timerPushed = false;
        }

        // ── Show device picker when one or more devices are found ──
        if (state == BLE_FOUND && !_menuShown) {
            _menuShown = true;
            var devices = _ble.getFoundDevices();
            var menu = new WatchUi.Menu2({:title => "Select Device"});
            for (var i = 0; i < devices.size(); i++) {
                var result = devices[i] as BluetoothLowEnergy.ScanResult;
                var name = result.getDeviceName();
                if (name == null || name.length() == 0) { name = "Unknown"; }
                menu.addItem(new WatchUi.MenuItem(name, null, result, {}));
            }
            WatchUi.pushView(menu, new DeviceMenuDelegate(_ble), WatchUi.SLIDE_UP);
            return;
        }

        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        // ── Clear ────────────────────────────────────────────
        dc.setColor(C_BG, C_BG);
        dc.clear();

        // ── Safe zone ────────────────────────────────────────
        // Round: inscribed-square inset ≈ h * 0.15
        // Rect : small fixed margin
        var inset  = _isRound ? (h * 0.15).toNumber() : 8;
        var safeT  = inset;
        var safeH  = h - inset * 2;

        // Anchor Y positions (all are vertical midpoints for drawText)
        var dotY  = safeT + (safeH * 0.14).toNumber();
        var mainY = safeT + (safeH * 0.50).toNumber();
        var txtY  = safeT + (safeH * 0.88).toNumber();

        // ── State dot ────────────────────────────────────────
        dc.setColor(_accentColor(state), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, dotY, DOT_R);

        // ── Main area ────────────────────────────────────────
        _drawMain(dc, w, cx, mainY, state);

        // ── Bottom text ──────────────────────────────────────
        var hint = _bottomText(state);
        if (hint.length() > 0) {
            dc.setColor(C_HINT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, txtY, Graphics.FONT_TINY, hint,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        _syncTimer();
    }

    // ----------------------------------------------------------
    //  Main area dispatcher
    // ----------------------------------------------------------
    hidden function _drawMain(
        dc    as Graphics.Dc,
        w     as Number,
        cx    as Number,
        cy    as Number,
        state as Number) as Void
    {
        if (state == BLE_SCANNING ||
            state == BLE_CONNECTING ||
            state == BLE_CONNECTED) {
            // Animated spinner — no card
            _drawSpinner(dc, cx, cy, _accentColor(state));
            return;
        }

        if (state == BLE_IDLE) {
            _drawCard(dc, w, cx, cy, "SCAN", null);
            return;
        }

        if (state == BLE_FOUND) {
            _drawCard(dc, w, cx, cy,
                _ble.getDeviceName(),
                _ble.getRssi().toString() + " dBm");
            return;
        }

        if (state == BLE_SUBSCRIBED) {
            _drawSubscribedCard(dc, w, cx, cy);
            return;
        }

        if (state == BLE_ERROR) {
            _drawCard(dc, w, cx, cy, "ERR", null);
            return;
        }
    }

    // ----------------------------------------------------------
    //  Rounded-rectangle card
    //  primary  — FONT_MEDIUM, white
    //  secondary — FONT_TINY, gray (pass null to omit)
    // ----------------------------------------------------------
    hidden function _drawCard(
        dc        as Graphics.Dc,
        w         as Number,
        cx        as Number,
        cy        as Number,
        primary   as String,
        secondary as String or Null) as Void
    {
        var fhMed  = dc.getFontHeight(Graphics.FONT_MEDIUM);
        var fhTiny = dc.getFontHeight(Graphics.FONT_TINY);
        var hasSec = (secondary != null && secondary.length() > 0);

        var cardW = (w * CARD_W_PCT).toNumber();
        var cardH = hasSec
            ? fhMed + fhTiny + CARD_PAD * 2 + 8
            : fhMed + CARD_PAD * 2;
        var cardX = cx - cardW / 2;
        var cardY = cy - cardH / 2;

        // Fill
        dc.setColor(C_CARD_FILL, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cardX, cardY, cardW, cardH, CARD_RADIUS);
        // Border
        dc.setPenWidth(2);
        dc.setColor(C_CARD_BORDER, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(cardX, cardY, cardW, cardH, CARD_RADIUS);
        dc.setPenWidth(1);

        if (hasSec) {
            // Two-line layout: treat primary+gap+secondary as a block,
            // center the block vertically within the card.
            var gap      = 8;
            var blockH   = fhMed + gap + fhTiny;
            var priY     = cy - blockH / 2 + fhMed / 2;
            var secY     = cy + blockH / 2 - fhTiny / 2;

            dc.setColor(C_TEXT_PRI, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, priY, Graphics.FONT_MEDIUM, primary,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            dc.setColor(C_TEXT_SEC, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, secY, Graphics.FONT_TINY, secondary,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.setColor(C_TEXT_PRI, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, Graphics.FONT_MEDIUM, primary,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // ----------------------------------------------------------
    //  Subscribed card — link status indicators + last alert label
    // ----------------------------------------------------------
    hidden function _drawSubscribedCard(
        dc as Graphics.Dc,
        w  as Number,
        cx as Number,
        cy as Number) as Void
    {
        var fhMed  = dc.getFontHeight(Graphics.FONT_MEDIUM);
        var fhTiny = dc.getFontHeight(Graphics.FONT_TINY);
        var gap    = 8;
        var cardW  = (w * CARD_W_PCT).toNumber();
        var cardH  = fhMed + gap + fhTiny + CARD_PAD * 2;
        var cardX  = cx - cardW / 2;
        var cardY  = cy - cardH / 2;

        // Card shell
        dc.setColor(C_CARD_FILL, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cardX, cardY, cardW, cardH, CARD_RADIUS);
        dc.setPenWidth(2);
        dc.setColor(C_CARD_BORDER, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(cardX, cardY, cardW, cardH, CARD_RADIUS);
        dc.setPenWidth(1);

        // ── Top row: D1 ● / ● D2 link indicators ─────────────
        // Two dots with labels, symmetrically placed around cx.
        var blockH  = fhMed + gap + fhTiny;
        var rowY    = cy - blockH / 2 + fhMed / 2;
        var dotR    = 6;
        var spacing = cardW / 4;   // offset from center to each pair

        // D1 — left of center
        var d1x = cx - spacing;
        var d1Color = _ble.getLinked1() ? C_ACC_LIVE : C_TEXT_SEC;
        dc.setColor(d1Color, Graphics.COLOR_TRANSPARENT);
        if (_ble.getLinked1()) {
            dc.fillCircle(d1x - dotR - 4, rowY, dotR);
        } else {
            dc.drawCircle(d1x - dotR - 4, rowY, dotR);
        }
        dc.drawText(d1x + 4, rowY, Graphics.FONT_MEDIUM, "D1",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // D2 — right of center
        var d2x = cx + spacing;
        var d2Color = _ble.getLinked2() ? C_ACC_LIVE : C_TEXT_SEC;
        dc.setColor(d2Color, Graphics.COLOR_TRANSPARENT);
        if (_ble.getLinked2()) {
            dc.fillCircle(d2x + dotR + 4, rowY, dotR);
        } else {
            dc.drawCircle(d2x + dotR + 4, rowY, dotR);
        }
        dc.drawText(d2x - 4, rowY, Graphics.FONT_MEDIUM, "D2",
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Bottom row: last alert label ──────────────────────
        var alertY = cy + blockH / 2 - fhTiny / 2;
        var notifType = _ble.getNotifType();
        var alertText = "--";
        var alertColor = C_TEXT_SEC;
        if (notifType == NOTIFY_LINKED) {
            alertText  = "LINKED";
            alertColor = C_ACC_LIVE;
        } else if (notifType == NOTIFY_ALERT_1) {
            alertText  = "ALERT  D1";
            alertColor = C_TEXT_PRI;
        } else if (notifType == NOTIFY_ALERT_2) {
            alertText  = "ALERT  D2";
            alertColor = C_TEXT_PRI;
        }
        dc.setColor(alertColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, alertY, Graphics.FONT_TINY, alertText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ----------------------------------------------------------
    //  Spinning arc
    //  A 120° colored arc rotates 60° per tick over 6 frames.
    //  A faint full circle sits behind it as a track.
    //  In CIQ drawArc: 0°=3 o'clock, 90°=12 o'clock, angles
    //  decrease clockwise.  ARC_CLOCKWISE draws start→end CW.
    // ----------------------------------------------------------
    hidden function _drawSpinner(
        dc     as Graphics.Dc,
        cx     as Number,
        cy     as Number,
        color  as Number) as Void
    {
        var r          = dc.getWidth() / 4;
        var startAngle = 90 - _animFrame * 60;
        var endAngle   = startAngle - 120;

        // Track
        dc.setPenWidth(SPINNER_PW);
        dc.setColor(0x222222, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);

        // Arc
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r,
            Graphics.ARC_CLOCKWISE, startAngle, endAngle);

        dc.setPenWidth(1);
    }

    // ----------------------------------------------------------
    //  Timer — runs only during animated states
    // ----------------------------------------------------------
    hidden function _syncTimer() as Void {
        var state    = _ble.getState();
        var needTick = (state == BLE_SCANNING   ||
                        state == BLE_CONNECTING  ||
                        state == BLE_CONNECTED);
        if (needTick && !_timerRunning) {
            _timer.start(method(:_onTick), 150, true);
            _timerRunning = true;
        } else if (!needTick && _timerRunning) {
            _timer.stop();
            _timerRunning = false;
            _animFrame    = 0;
        }
    }

    function _onTick() as Void {
        _animFrame = (_animFrame + 1) % 6;
        WatchUi.requestUpdate();
    }

    // ----------------------------------------------------------
    //  State → accent color
    // ----------------------------------------------------------
    hidden function _accentColor(state as Number) as Number {
        if (state == BLE_IDLE)       { return C_ACC_IDLE;   }
        if (state == BLE_SCANNING)   { return C_ACC_ACTIVE; }
        if (state == BLE_FOUND)      { return C_ACC_FOUND;  }
        if (state == BLE_CONNECTING) { return C_ACC_ACTIVE; }
        if (state == BLE_CONNECTED)  { return C_ACC_ACTIVE; }
        if (state == BLE_SUBSCRIBED) { return C_ACC_LIVE;   }
        if (state == BLE_ERROR)      { return C_ACC_ERROR;  }
        return C_ACC_IDLE;
    }

    // ----------------------------------------------------------
    //  State → single bottom line  (muted, lowercase)
    // ----------------------------------------------------------
    hidden function _bottomText(state as Number) as String {
        if (state == BLE_IDLE)       { return "tap to scan";       }
        if (state == BLE_SCANNING)   { return "back to stop";      }
        if (state == BLE_FOUND)      { return "tap  |  back=rescan"; }
        if (state == BLE_CONNECTING) { return "connecting...";     }
        if (state == BLE_CONNECTED)  { return "enabling notify..."; }
        if (state == BLE_SUBSCRIBED) { return "back to disconnect"; }
        if (state == BLE_ERROR)      { return _ble.getStatus();    }
        return "";
    }

}
