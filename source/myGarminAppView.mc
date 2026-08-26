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
//   50%  main area     — card, spinner, or live screen
//                        (big match-timer digits + AR symbols)
//   88%  bottom text   — single short line, very muted
// ============================================================

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
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
const C_COUNTUP     = 0x55AAEE;  // soft blue — secondary count-up digits

// ── Geometry ─────────────────────────────────────────────────
const CARD_PAD    = 14;   // px padding inside card
const CARD_RADIUS = 10;   // corner radius px
const CARD_W_PCT  = 0.72; // card width as fraction of screen width
const DOT_R       = 5;    // state dot radius px
const SPINNER_PW  = 4;    // spinner arc pen width px

// Garmin number fonts report ~40-50% more height than the visual
// glyphs (metric padding).  Scale down for stacking math so the
// count-up / AR row hug the digits instead of the padded box.
// 0.55 was validated on-device by the earlier timer branch.
const CD_VIS_SCALE = 0.55;

// Vector-font sizing: digit (cap) height as a fraction of the
// requested em size — Roboto lining figures are ≈ 0.71 em.
const CD_VEC_CAP = 0.70;

class myGarminAppView extends WatchUi.View {

    hidden var _ble          as BleManager;
    hidden var _matchTimer   as MatchTimer;
    hidden var _timer        as Timer.Timer;
    hidden var _tickPeriod   as Number  = 0;   // current tick period ms, 0 = stopped
    hidden var _animFrame    as Number  = 0;   // 0-11 (spinner uses %6, blink uses %4)
    hidden var _isRound      as Boolean = false;
    hidden var _arIcon       as Graphics.BitmapType;   // paging-alert icon

    // Live-screen layout — computed once in onLayout().  _cdFont is
    // the largest number font that fits this screen; _cdVisH its
    // approximate visual glyph height (font height × CD_VIS_SCALE).
    // The whole stack (AR row / countdown / count-up) is centered in
    // the band between the top margin and the hint line, so these
    // anchors replace the generic mainY anchor on the live screen.
    hidden var _cdFont       as Graphics.FontDefinition = Graphics.FONT_NUMBER_MEDIUM;
    hidden var _cdVisH       as Number  = 0;
    hidden var _cdY          as Number  = 0;   // countdown vertical midpoint
    hidden var _symY         as Number  = 0;   // AR symbol row midpoint
    hidden var _cuY          as Number  = 0;   // count-up vertical midpoint

    function initialize(ble as BleManager, matchTimer as MatchTimer) {
        View.initialize();
        _ble        = ble;
        _matchTimer = matchTimer;
        _timer      = new Timer.Timer();
        _arIcon     = WatchUi.loadResource(Rez.Drawables.ArIcon) as Graphics.BitmapType;
        // Detect screen shape once — doesn't change at runtime
        var shape = System.getDeviceSettings().screenShape;
        _isRound = (shape == System.SCREEN_SHAPE_ROUND ||
                    shape == System.SCREEN_SHAPE_SEMI_ROUND);
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _pickCountdownFont(dc);
    }

    function onShow() as Void {
        // Zero-touch flow: kick off the scan as soon as the app opens.
        // Not re-triggered once live (e.g. after a menu Disconnect).
        var state = _ble.getState();
        if (!_ble.isLive() && (state == BLE_IDLE || state == BLE_ERROR)) {
            _ble.startScan();
        }
        _syncTimer();
        WatchUi.requestUpdate();
    }

    function onHide() as Void {
        _timer.stop();
        _tickPeriod = 0;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        // ── Clear ────────────────────────────────────────────
        dc.setColor(C_BG, C_BG);
        dc.clear();

        // Scan-deadline fallback rides the animation tick.
        _ble.checkScanTimeout();
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
        // Skipped on the live screen — every pixel goes to the timer,
        // even while a background rescan is running.
        if (!_ble.isLive()) {
            dc.setColor(_accentColor(state), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, dotY, DOT_R);
        }

        // ── Main area ────────────────────────────────────────
        _drawMain(dc, w, cx, mainY, state);

        // ── Bottom text (pre-live phases only) ───────────────
        if (!_ble.isLive()) {
            var hint = _bottomText(state);
            if (hint.length() > 0) {
                dc.setColor(C_HINT, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, txtY, Graphics.FONT_TINY, hint,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
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
        // Live is latched — once the timer screen is up it stays up,
        // regardless of what BLE is doing in the background.
        if (_ble.isLive()) {
            _drawLiveScreen(dc, w, cx, cy);
            return;
        }

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
    //  Live (subscribed) screen — match timers + AR symbols
    //
    //  Vertical stack, all centered on the column so the layout
    //  stays inside a round screen's usable area:
    //    AR symbol row (above the digits)
    //    COUNTDOWN — big numbers, center stage
    //                (white running, gray paused, amber in
    //                 stoppage time after expiry)
    //    COUNT-UP  — secondary: smaller, soft blue, synchronized
    //
    //  Each linked AR renders as a shape symbol with its number
    //  inside (placeholder art until custom icons exist):
    //    AR1 — circle outline
    //    AR2 — triangle outline
    //  An unlinked AR draws nothing.  While an AR's alert window
    //  is open the symbol blinks (~300 ms phases) between its
    //  default shape and a contrasting filled diamond.
    // ----------------------------------------------------------
    hidden function _drawLiveScreen(
        dc as Graphics.Dc,
        w  as Number,
        cx as Number,
        cy as Number) as Void
    {
        // ── Countdown — biggest font this screen can hold ────
        // All vertical anchors were precomputed in onLayout().
        var cdColor = _matchTimer.isRunning()
            ? (_matchTimer.isExpired() ? C_ACC_ALERT : C_TEXT_PRI)
            : C_TEXT_SEC;
        dc.setColor(cdColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, _cdY, _cdFont,
            _matchTimer.formatCountdown(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Count-up — secondary, right below the countdown ──
        dc.setColor(C_COUNTUP, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, _cuY, Graphics.FONT_MEDIUM,
            _matchTimer.formatCountUp(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Paging-alert flash above the digits ──────────────
        // Idle: nothing — the live screen is just the timers.  During
        // an AR's alert window the AR icon flashes (300 ms phases)
        // with the AR number beside it.
        var a1 = _ble.isAlerting1();
        var a2 = _ble.isAlerting2();
        if (!a1 && !a2) { return; }
        if ((_animFrame % 4) >= 2) { return; }     // flash off-phase

        var num    = a1 ? (a2 ? "1 2" : "1") : "2";
        var iconW  = _arIcon.getWidth();
        var iconH  = _arIcon.getHeight();
        var gap    = 8;
        var numW   = dc.getTextWidthInPixels(num, Graphics.FONT_LARGE);
        var left   = cx - (iconW + gap + numW) / 2;
        dc.drawBitmap(left, _symY - iconH / 2, _arIcon);
        dc.setColor(C_ACC_ALERT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + iconW + gap, _symY, Graphics.FONT_LARGE, num,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ----------------------------------------------------------
    //  Countdown font selection — run once per layout.
    //
    //  Seeing the timer at a glance is this app's top priority: the
    //  countdown is dead-centered on the screen and there is no hint
    //  line on the live screen.  The only hard floor is the count-up
    //  fitting between the digits and the bottom of the screen (disc
    //  chord on round faces).  The AR symbol row is NOT reserved —
    //  it floats in whatever gap remains above the digits (clamped
    //  to the screen edge).
    //
    //  Two candidates compete and the taller countdown wins:
    //   1. the largest system number font that fits, and
    //   2. a vector font (CIQ 4.2.1+, needs scalable faces on the
    //      device — venu3-gen and newer; returns null elsewhere)
    //      sized continuously against the same constraints.
    //
    //  Width limit: rectangle screens use the full width; round
    //  screens use the chord at the digits' top/bottom rows, so a
    //  tall font can never push its corners off the disc.
    // ----------------------------------------------------------
    hidden function _pickCountdownFont(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        var c = h / 2;

        var cuVis = (dc.getFontHeight(Graphics.FONT_MEDIUM) * 0.60).toNumber();

        // Lowest row the count-up's bottom may reach: screen bottom on
        // rectangles, or the disc row where the chord still clears the
        // count-up's own width on round screens.
        var maxYB;
        if (_isRound) {
            var cuHalf = dc.getTextWidthInPixels("88:88", Graphics.FONT_MEDIUM) / 2 + 6;
            maxYB = c + Math.sqrt((c * c - cuHalf * cuHalf).toFloat()).toNumber() - 2;
        } else {
            maxYB = h - 4;
        }
        // Countdown is centered at c, so its half-height is bounded by
        // what still leaves room for the count-up below.
        var maxVis = (maxYB - 2 - cuVis - c) * 2;

        // ── Candidate 1: largest fitting system number font ──
        var bestFont = Graphics.FONT_NUMBER_MILD as Graphics.FontType;
        var bestVis  = (dc.getFontHeight(Graphics.FONT_NUMBER_MILD) * CD_VIS_SCALE).toNumber();
        var fonts = [
            Graphics.FONT_NUMBER_THAI_HOT,
            Graphics.FONT_NUMBER_HOT,
            Graphics.FONT_NUMBER_MEDIUM
        ] as Array<Graphics.FontDefinition>;
        for (var i = 0; i < fonts.size(); i++) {
            var vis = (dc.getFontHeight(fonts[i]) * CD_VIS_SCALE).toNumber();
            if (vis <= maxVis &&
                dc.getTextWidthInPixels("88:88", fonts[i]) <= _cdMaxWidth(dc, vis)) {
                bestFont = fonts[i];
                bestVis  = vis;
                break;
            }
        }

        // ── Candidate 2: vector font, sized to the same budget ──
        // Binary-search the largest glyph height whose "88:88" fits
        // its own row's chord.  Only adopted when it beats the system
        // font — on devices whose widest available face is plain
        // Roboto (e.g. venu3-gen) THAI_HOT may win; the Condensed
        // faces on CIQ-6 devices are where it pays.
        var usedVector = false;
        if (Graphics has :getVectorFont) {
            var lo = bestVis;      // floor: must beat this
            var hi = maxVis;       // ceiling: height budget
            for (var iter = 0; iter < 7 && hi - lo > 2; iter++) {
                var vis = (lo + hi) / 2;
                var vf  = Graphics.getVectorFont(
                    {:face => ["RobotoCondensedBold", "RobotoCondensedRegular",
                               "RobotoRegular", "Roboto"],
                     :size => (vis / CD_VEC_CAP).toNumber()});
                if (vf != null &&
                    dc.getTextWidthInPixels("88:88", vf) <= _cdMaxWidth(dc, vis)) {
                    bestFont   = vf;
                    bestVis    = vis;
                    usedVector = true;
                    lo = vis;      // fits — try bigger
                } else {
                    hi = vis;      // too wide (or size capped) — go smaller
                }
            }
        }

        // ── Apply: countdown centered, count-up below, alert above ──
        var iconHalf = _arIcon.getHeight() / 2;
        _cdFont = bestFont;
        _cdVisH = bestVis;
        _cdY    = c;
        _cuY    = c + bestVis / 2 + 2 + cuVis / 2;
        // The alert flash floats above the digits; clamp to the screen
        // edge and accept overlap on tight screens — the timer wins.
        _symY = c - bestVis / 2 - 6 - iconHalf;
        if (_symY < iconHalf + 2) { _symY = iconHalf + 2; }
        System.println("View: countdown visH=" + _cdVisH + " cdY=" + _cdY +
            " vector=" + (usedVector ? "yes" : "no"));
    }

    // Max countdown text width with the digits centered on the screen:
    // rectangles use the full width, round screens the chord at the
    // digits' top/bottom rows (dy = vis/2 from the disc center).
    hidden function _cdMaxWidth(dc as Graphics.Dc, vis as Number) as Number {
        var w = dc.getWidth();
        if (!_isRound) { return w - 12; }
        var c  = dc.getHeight() / 2;
        var dy = vis / 2;
        if (dy >= c) { return 0; }
        var half = Math.sqrt((c * c - dy * dy).toFloat());
        return (half.toNumber() - 6) * 2;
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
    //  Tick source — two speeds:
    //   150 ms  spinner states, or an AR alert blink window open
    //   500 ms  match timer running (keeps the seconds display fresh)
    //   stopped otherwise
    // ----------------------------------------------------------
    hidden function _syncTimer() as Void {
        var state = _ble.getState();
        var fast  = (state == BLE_SCANNING   ||
                     state == BLE_CONNECTING  ||
                     state == BLE_CONNECTED)  ||
                    (_ble.isLive() &&
                     (_ble.isAlerting1() || _ble.isAlerting2()));
        var slow  = (_ble.isLive() && _matchTimer.isRunning());

        var period = fast ? 150 : (slow ? 500 : 0);
        if (period == _tickPeriod) { return; }

        _timer.stop();
        if (period > 0) {
            _timer.start(method(:_onTick), period, true);
        } else {
            _animFrame = 0;
        }
        _tickPeriod = period;
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
        if (state == BLE_SCANNING)   { return "finding relay...  back=skip"; }
        if (state == BLE_CONNECTING) { return "connecting...  back=skip"; }
        if (state == BLE_CONNECTED)  { return "enabling notify..."; }
        // Live screen: no hint — every pixel goes to the timer
        // (BACK opens the settings menu).
        if (state == BLE_ERROR)      { return _ble.getStatus();    }
        return "";
    }

}
