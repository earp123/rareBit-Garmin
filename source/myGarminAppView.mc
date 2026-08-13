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
//   50%  main area     — card, spinner, or AR symbols
//   88%  bottom text   — single short line, very muted
// ============================================================

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
const C_ACC_ALERT   = 0xFFAA00;  // amber — AR alert blink contrast symbol

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
    hidden var _animFrame    as Number  = 0;   // 0-11 (spinner uses %6, blink uses %4)
    hidden var _isRound      as Boolean = false;

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
        _syncTimer();
        WatchUi.requestUpdate();
    }

    function onHide() as Void {
        _timer.stop();
        _timerRunning = false;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        // ── Clear ────────────────────────────────────────────
        dc.setColor(C_BG, C_BG);
        dc.clear();

        var state = _ble.getState();

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
            _drawArStatus(dc, w, cx, cy);
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
    //  Subscribed screen — symbol-forward AR status
    //
    //  Each linked AR renders as a large shape symbol with its
    //  number inside (placeholder art until custom icons exist):
    //    AR1 — circle outline
    //    AR2 — triangle outline
    //  An unlinked AR draws nothing.  While an AR's alert window
    //  is open the symbol blinks (~300 ms phases) between its
    //  default shape and a contrasting filled diamond.
    // ----------------------------------------------------------
    hidden function _drawArStatus(
        dc as Graphics.Dc,
        w  as Number,
        cx as Number,
        cy as Number) as Void
    {
        // Show a symbol while linked, or while its alert is still
        // blinking (so an alert stays visible even on an unlink race).
        var show1 = _ble.getLinked1() || _ble.isAlerting1();
        var show2 = _ble.getLinked2() || _ble.isAlerting2();

        if (!show1 && !show2) {
            dc.setColor(C_TEXT_SEC, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, Graphics.FONT_TINY, "no ARs linked",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var r       = (w * 0.14).toNumber();       // symbol radius
        var blinkOn = (_animFrame % 4) < 2;        // 300 ms on / 300 ms off

        if (show1 && show2) {
            var off = (w * 0.18).toNumber();
            _drawArSymbol(dc, cx - off, cy, r, 1, _ble.isAlerting1() && blinkOn);
            _drawArSymbol(dc, cx + off, cy, r, 2, _ble.isAlerting2() && blinkOn);
        } else if (show1) {
            _drawArSymbol(dc, cx, cy, r, 1, _ble.isAlerting1() && blinkOn);
        } else {
            _drawArSymbol(dc, cx, cy, r, 2, _ble.isAlerting2() && blinkOn);
        }
    }

    // Draw one AR symbol centered at (x, y) with circumradius r.
    // contrast=true draws the alert-blink contrast symbol instead
    // of the AR's default shape.
    hidden function _drawArSymbol(
        dc       as Graphics.Dc,
        x        as Number,
        y        as Number,
        r        as Number,
        arNum    as Number,
        contrast as Boolean) as Void
    {
        if (contrast) {
            // Contrast symbol — filled diamond, number inverted.
            dc.setColor(C_ACC_ALERT, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[x, y - r], [x + r, y], [x, y + r], [x - r, y]]);
            dc.setColor(C_BG, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setPenWidth(3);
            dc.setColor(C_ACC_LIVE, Graphics.COLOR_TRANSPARENT);
            if (arNum == 1) {
                dc.drawCircle(x, y, r);
            } else {
                // Triangle with vertices on the circumradius (centroid = center)
                var ax = x;
                var ay = y - r;
                var bx = x - (r * 0.87).toNumber();
                var by = y + (r * 0.5).toNumber();
                var ex = x + (r * 0.87).toNumber();
                var ey = y + (r * 0.5).toNumber();
                dc.drawLine(ax, ay, bx, by);
                dc.drawLine(bx, by, ex, ey);
                dc.drawLine(ex, ey, ax, ay);
            }
            dc.setPenWidth(1);
            dc.setColor(C_TEXT_PRI, Graphics.COLOR_TRANSPARENT);
        }

        dc.drawText(x, y, Graphics.FONT_LARGE, arNum.toString(),
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
        var startAngle = 90 - (_animFrame % 6) * 60;
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
    //  Timer — runs during animated states (spinner) and while an
    //  AR alert blink window is open
    // ----------------------------------------------------------
    hidden function _syncTimer() as Void {
        var state    = _ble.getState();
        var needTick = (state == BLE_SCANNING   ||
                        state == BLE_CONNECTING  ||
                        state == BLE_CONNECTED)  ||
                       (state == BLE_SUBSCRIBED &&
                        (_ble.isAlerting1() || _ble.isAlerting2()));
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
        // 12 is divisible by both the spinner cycle (6 frames) and the
        // blink cycle (4 frames), so neither jumps at the wraparound.
        _animFrame = (_animFrame + 1) % 12;
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
