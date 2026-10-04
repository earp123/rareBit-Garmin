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
// Connect screen (pre-live phases), stacked within the safe zone:
//   42%  app icon, wrapped in the state ring (spinner while
//        scanning / connecting, track only idle, red on error)
//        "rareBit", then a status line and a muted hint line
//
// The live screen ignores the safe zone: it is laid out once in
// onLayout() around the biggest countdown the screen can hold
// (see _pickCountdownFont), with the progress ring and link dot
// out in the bezel margin.
// ============================================================

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// ── Colors ───────────────────────────────────────────────────
// Accents match the rareBit iOS / Android apps.  AMOLED: the neon
// green is for thin strokes and small marks only, never big fills.
const C_BG          = Graphics.COLOR_BLACK;
const C_TEXT_PRI    = Graphics.COLOR_WHITE;
const C_TEXT_SEC    = 0x888888;
const C_HINT        = 0x444444;

const C_ACC_IDLE    = 0x555555;
const C_ACC_ACTIVE  = 0xFFC300;  // amber — scanning, connecting, expiry
const C_ACC_LIVE    = 0x39FF14;  // neon green — relay linked / live
const C_ACC_ERROR   = 0xFF3B30;  // red
const C_ACC_ALERT   = 0xFFC300;  // amber — AR alert flash label
const C_COUNTUP     = 0x00CFFF;  // cyan — secondary count-up digits
const C_TOD         = 0x66CC88;  // soft green — time-of-day line above the countdown
const C_STOPPAGE    = 0xFF9500;  // orange — stoppage line, in the time-of-day slot
const C_RING_TRACK  = 0x1C1C1C;  // unfilled part of the progress / state rings

// ── Geometry ─────────────────────────────────────────────────
const SPINNER_PW  = 4;    // connect-screen state ring pen width px
const SPINNER_GAP = 12;   // state ring radius beyond the icon's half-size
const RING_INSET  = 4;    // progress ring radius = h/2 - RING_INSET
const RING_PW     = 3;    // progress ring (or rect top bar) pen width px
const LINK_DOT_R  = 3;    // link dot radius px
const STOP_DOT_R  = 4;    // "segment open" dot left of the stoppage line

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
    hidden var _logo         as Graphics.BitmapType;   // app icon, connect screen

    // Live-screen layout — computed once in onLayout().  _cdFont is
    // the largest number font that fits this screen; _cdVisH its
    // approximate visual glyph height (font height × CD_VIS_SCALE).
    // The whole stack (AR row / countdown / count-up) is centered in
    // the band between the top margin and the hint line, so these
    // anchors replace the generic mainY anchor on the live screen.
    hidden var _cdFont       as Graphics.FontDefinition = Graphics.FONT_NUMBER_MEDIUM;
    hidden var _cdVisH       as Number  = 0;
    hidden var _cdY          as Number  = 0;   // countdown vertical midpoint
    hidden var _symY         as Number  = 0;   // alert-flash row midpoint
    hidden var _cuY          as Number  = 0;   // count-up vertical midpoint
    hidden var _todY         as Number  = 0;   // time-of-day vertical midpoint
    hidden var _tagY         as Number  = 0;   // half-tag midpoint, 0 = doesn't fit

    function initialize(ble as BleManager, matchTimer as MatchTimer) {
        View.initialize();
        _ble        = ble;
        _matchTimer = matchTimer;
        _timer      = new Timer.Timer();
        _arIcon     = WatchUi.loadResource(Rez.Drawables.ArIcon) as Graphics.BitmapType;
        _logo       = WatchUi.loadResource(Rez.Drawables.LauncherIcon) as Graphics.BitmapType;
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

        // Scan-deadline fallback and the paused-clock reminder both ride
        // the view tick instead of owning Timers of their own.
        _ble.checkScanTimeout();
        _matchTimer.pollPauseReminder();

        // Live is latched — once the timer screen is up it stays up,
        // regardless of what BLE is doing in the background.
        if (_ble.isLive()) {
            _drawLiveScreen(dc, w, h, cx);
        } else {
            _drawConnectScreen(dc, h, cx, _ble.getState());
        }

        _syncTimer();
    }

    // ----------------------------------------------------------
    //  Connect screen — every pre-live state shares one layout:
    //
    //    app icon       — centered at 42% of the safe zone, wrapped
    //                     in the state ring (the ring carries state:
    //                     spinner while scanning / connecting, bare
    //                     track when idle, solid red on error)
    //    "rareBit"      — FONT_SMALL, directly under the ring
    //    status line    — FONT_XTINY, what BLE is doing
    //    hint line      — FONT_XTINY, muted: the one useful input
    // ----------------------------------------------------------
    hidden function _drawConnectScreen(
        dc    as Graphics.Dc,
        h     as Number,
        cx    as Number,
        state as Number) as Void
    {
        // Round: inscribed-square inset ≈ h * 0.15.  Rect: small margin.
        var inset = _isRound ? (h * 0.15).toNumber() : 8;
        var safeH = h - inset * 2;
        var iconY = inset + (safeH * 0.42).toNumber();

        var iconW = _logo.getWidth();
        var iconH = _logo.getHeight();
        dc.drawBitmap(cx - iconW / 2, iconY - iconH / 2, _logo);

        var r = (iconW > iconH ? iconW : iconH) / 2 + SPINNER_GAP;
        _drawStateRing(dc, cx, iconY, r, state);

        // Text stack — each line sits on its font's full height, which
        // already carries the leading between lines.
        var fhS = dc.getFontHeight(Graphics.FONT_SMALL);
        var fhX = dc.getFontHeight(Graphics.FONT_XTINY);
        var y   = iconY + r + SPINNER_PW / 2 + 4;

        dc.setColor(C_TEXT_PRI, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + fhS / 2, Graphics.FONT_SMALL, "rareBit",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        y += fhS;

        dc.setColor(C_TEXT_SEC, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + fhX / 2, Graphics.FONT_XTINY, _statusText(state),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        y += fhX;

        var hint = _hintText(state);
        if (hint.length() > 0) {
            dc.setColor(C_HINT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y + fhX / 2, Graphics.FONT_XTINY, hint,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // State ring around the connect-screen icon.
    hidden function _drawStateRing(
        dc    as Graphics.Dc,
        cx    as Number,
        cy    as Number,
        r     as Number,
        state as Number) as Void
    {
        if (state == BLE_SCANNING   ||
            state == BLE_CONNECTING ||
            state == BLE_CONNECTED) {
            _drawSpinner(dc, cx, cy, r, _accentColor(state));
            return;
        }
        _setAntiAlias(dc, true);
        dc.setPenWidth(SPINNER_PW);
        // Error: a full red ring.  Idle (or anything else): track only.
        dc.setColor(state == BLE_ERROR ? C_ACC_ERROR : C_RING_TRACK,
            Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        dc.setPenWidth(1);
        _setAntiAlias(dc, false);
    }

    // ----------------------------------------------------------
    //  Live screen — match timers, time of day, alert flash
    //
    //  Vertical stack, all centered on the column so the layout
    //  stays inside a round screen's usable area:
    //    TIME OF DAY — soft green, count-up size, above the digits
    //                  (yields to the orange stoppage line — see below)
    //    COUNTDOWN   — big numbers, center stage
    //                  (white running, gray paused, amber in
    //                   stoppage time after expiry)
    //    COUNT-UP    — secondary: smaller, cyan; the running clock —
    //                  starts with the first SELECT and never pauses,
    //                  so it visibly keeps moving while the countdown
    //                  sits gray
    //    HALF TAG    — "1st" / "2nd", tiny and muted, below the
    //                  count-up — only on screens with room to spare
    //
    //  Out in the bezel margin, clear of the stack:
    //    PROGRESS RING — countdown progress, clockwise from 12
    //                  o'clock (a top-edge bar on rectangles)
    //    LINK DOT    — 12 o'clock, green while the relay is
    //                  subscribed, gray in timer-only / dropped
    //
    //  While an alert window is open (ALERT_BLINK_MS) the flag icon
    //  flashes in 300 ms phases above the digits, labelled with what
    //  paged: the AR number for a long press ("1", "2"), "S" for a
    //  short press (Alert 3 — the relay doesn't say which flag), or
    //  all of them while windows overlap ("1 S", "1 2 S").  It takes
    //  over the time-of-day line for the duration.
    //
    //  That top slot has three tenants, in priority order: the alert
    //  flash, then the Stoppage Timer's orange "+MM:SS" (shown once the
    //  setting is on and anything has been timed this half, with a dot
    //  while a stoppage is open), then the wall clock.  The stoppage
    //  keeps counting under an alert and reappears when the flash
    //  window closes; the countdown never gives up a pixel to any of
    //  them.
    // ----------------------------------------------------------
    hidden function _drawLiveScreen(
        dc as Graphics.Dc,
        w  as Number,
        h  as Number,
        cx as Number) as Void
    {
        // ── Bezel margin: progress ring, link dot ────────────
        _drawProgressRing(dc, w, h, cx);
        dc.setColor(_ble.getState() == BLE_SUBSCRIBED ? C_ACC_LIVE : C_ACC_IDLE,
            Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, _isRound ? 10 : 8, LINK_DOT_R);

        // ── Countdown — biggest font this screen can hold ────
        // All vertical anchors were precomputed in onLayout().
        var cdColor = _matchTimer.isRunning()
            ? (_matchTimer.isExpired() ? C_ACC_ACTIVE : C_TEXT_PRI)
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

        // ── Half tag — only where onLayout found room ────────
        if (_tagY > 0) {
            dc.setColor(C_HINT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, _tagY, Graphics.FONT_XTINY,
                _matchTimer.isSecondHalf() ? "2nd" : "1st",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // ── Time of day, or the alert flash ──────────────
        // Idle: the wall clock.  During an AR's alert window the flag
        // icon flashes (300 ms phases) with the AR number beside it, and
        // the clock line yields to it so the two never overlap.
        var a1 = _ble.isAlerting1();
        var a2 = _ble.isAlerting2();
        var a3 = _ble.isAlerting3();
        if (!a1 && !a2 && !a3) {
            if (_matchTimer.isStoppageEnabled() && _matchTimer.hasStoppage()) {
                _drawStoppageLine(dc, cx);
            } else {
                dc.setColor(C_TOD, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, _todY, Graphics.FONT_MEDIUM, _timeOfDay(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
            return;
        }
        if ((_animFrame % 4) >= 2) { return; }     // flash off-phase

        var num    = _alertLabel(a1, a2, a3);
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

    // Flash label: open windows in order, space-separated — "1", "2",
    // "S", "1 2", "1 S", "2 S", "1 2 S".
    hidden function _alertLabel(a1 as Boolean, a2 as Boolean, a3 as Boolean) as String {
        var s = a1 ? "1" : "";
        if (a2) { s = (s.length() > 0) ? s + " 2" : "2"; }
        if (a3) { s = (s.length() > 0) ? s + " S" : "S"; }
        return s;
    }

    // Stoppage line, in the time-of-day slot: orange "+MM:SS" of the
    // half's stoppage so far.  The text stays centered whether or not a
    // segment is open — the open-segment dot hangs off its left edge
    // rather than shifting it.  (A drawn dot, not a "●" glyph: not every
    // device font carries one.)
    hidden function _drawStoppageLine(dc as Graphics.Dc, cx as Number) as Void {
        var txt = "+" + _matchTimer.formatStoppage();
        dc.setColor(C_STOPPAGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, _todY, Graphics.FONT_MEDIUM, txt,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (_matchTimer.isStoppageOpen()) {
            var half = dc.getTextWidthInPixels(txt, Graphics.FONT_MEDIUM) / 2;
            dc.fillCircle(cx - half - 6 - STOP_DOT_R, _todY, STOP_DOT_R);
        }
    }

    // Countdown progress in the bezel margin.  Round: a thin ring at
    // h/2 - RING_INSET, filled clockwise from 12 o'clock as the interval
    // elapses.  Rectangle: the same rule as a bar along the top edge.
    // Green running, gray paused, solid amber once expired; before the
    // first start only the track shows.  Redrawn on the view's existing
    // tick — no timer of its own.
    hidden function _drawProgressRing(
        dc as Graphics.Dc,
        w  as Number,
        h  as Number,
        cx as Number) as Void
    {
        var interval = _matchTimer.getIntervalMs();
        var expired  = _matchTimer.isExpired();
        // Float: elapsed × 360 overflows a 32-bit Number on long intervals.
        var frac = expired ? 1.0
            : _matchTimer.getElapsedMs().toFloat() / interval.toFloat();
        var fill = expired ? C_ACC_ACTIVE
            : (_matchTimer.isRunning() ? C_ACC_LIVE : C_TEXT_SEC);

        if (!_isRound) {
            dc.setColor(C_RING_TRACK, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(0, 0, w, RING_PW);
            var barW = (w * frac).toNumber();
            if (barW > 0) {
                dc.setColor(fill, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(0, 0, barW, RING_PW);
            }
            return;
        }

        var cy = h / 2;
        var r  = cy - RING_INSET;
        _setAntiAlias(dc, true);
        dc.setPenWidth(RING_PW);
        dc.setColor(C_RING_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        dc.setColor(fill, Graphics.COLOR_TRANSPARENT);
        if (expired) {
            dc.drawCircle(cx, cy, r);
        } else {
            // drawArc: 0° = 3 o'clock, 90° = 12 o'clock, clockwise
            // decreases the angle.  Under a degree there's nothing to see.
            var deg = (360.0 * frac).toNumber();
            if (deg >= 1) {
                dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 90, 90 - deg);
            }
        }
        dc.setPenWidth(1);
        _setAntiAlias(dc, false);
    }

    // Anti-aliased strokes where the device supports them (CIQ 3.2+);
    // thin rings look ragged on the high-density AMOLEDs without it.
    hidden function _setAntiAlias(dc as Graphics.Dc, on as Boolean) as Void {
        if (dc has :setAntiAlias) { dc.setAntiAlias(on); }
    }

    // Wall clock, digits only: "HH:MM" (24 h) or "h:MM" (12 h, no AM/PM
    // — the official knows which it is, and the line stays one clean
    // centered block).
    hidden function _timeOfDay() as String {
        var t = System.getClockTime();
        var h = t.hour;
        if (System.getDeviceSettings().is24Hour) {
            return h.format("%02d") + ":" + t.min.format("%02d");
        }
        h = h % 12;
        if (h == 0) { h = 12; }
        return h.toString() + ":" + t.min.format("%02d");
    }

    // ----------------------------------------------------------
    //  Countdown font selection — run once per layout.
    //
    //  Seeing the timer at a glance is this app's top priority: the
    //  countdown is dead-centered on the screen and there is no hint
    //  line on the live screen.  The only hard floor is the count-up
    //  fitting between the digits and the bottom of the screen (disc
    //  chord on round faces).  Nothing above the digits is reserved:
    //  the time-of-day line mirrors the count-up's slot (so it fits by
    //  symmetry whenever the count-up does) and the alert flash floats
    //  in whatever gap remains (clamped to the screen edge).  The
    //  progress ring and link dot live in the bezel margin outside all
    //  of this, and the half tag only appears if room is left over —
    //  none of them can cost the countdown a pixel.
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
        // Time of day mirrors the count-up's slot above the digits.  The
        // disc is symmetric, so "88:88" fits there whenever the count-up
        // fits below (the line is digits only — no AM/PM suffix).
        _todY = c - bestVis / 2 - 2 - cuVis / 2;
        // The alert flash floats above the digits; clamp to the screen
        // edge and accept overlap on tight screens — the timer wins.
        _symY = c - bestVis / 2 - 6 - iconHalf;
        if (_symY < iconHalf + 2) { _symY = iconHalf + 2; }

        // Half tag below the count-up, only if it still clears the
        // bottom: the chord inside the progress ring's stroke on round
        // faces (same test as the count-up's), the screen edge on
        // rectangles.  No room, no tag — it never shrinks the countdown.
        var fhX    = dc.getFontHeight(Graphics.FONT_XTINY);
        var tagBot = _cuY + cuVis / 2 + 4 + fhX;
        var tagMax = h - 4;
        var ringIn = c - RING_INSET - RING_PW;   // just inside the stroke
        if (_isRound) {
            var tagHalf = dc.getTextWidthInPixels("2nd", Graphics.FONT_XTINY) / 2 + 6;
            tagMax = c + Math.sqrt((ringIn * ringIn - tagHalf * tagHalf).toFloat()).toNumber() - 2;
        }
        _tagY = (tagBot <= tagMax) ? tagBot - fhX / 2 : 0;

        // Ring clearance (round): how far the countdown's and count-up's
        // text-box corners sit inside the ring stroke.  Negative = the
        // ring crosses that box corner — check the digits in the sim.
        var ringMsg = "";
        if (_isRound) {
            var cdHalfW = dc.getTextWidthInPixels("88:88", bestFont) / 2;
            var cuHalfW = dc.getTextWidthInPixels("88:88", Graphics.FONT_MEDIUM) / 2;
            var cdDy    = bestVis / 2;
            var cuDy    = _cuY + cuVis / 2 - c;
            var cdR = Math.sqrt((cdHalfW * cdHalfW + cdDy * cdDy).toFloat()).toNumber();
            var cuR = Math.sqrt((cuHalfW * cuHalfW + cuDy * cuDy).toFloat()).toNumber();
            ringMsg = " ringClr cd=" + (ringIn - cdR) + " cu=" + (ringIn - cuR);
        }
        System.println("View: countdown visH=" + _cdVisH + " cdY=" + _cdY +
            " todY=" + _todY +
            " vector=" + (usedVector ? "yes" : "no") + ringMsg +
            " halfTag=" + (_tagY > 0 ? "yes" : "no"));
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
    //  Spinning arc, radius r around (cx, cy)
    //  A 120° colored arc rotates 60° per tick over 6 frames.
    //  A faint full circle sits behind it as a track.
    //  In CIQ drawArc: 0°=3 o'clock, 90°=12 o'clock, angles
    //  decrease clockwise.  ARC_CLOCKWISE draws start→end CW.
    // ----------------------------------------------------------
    hidden function _drawSpinner(
        dc     as Graphics.Dc,
        cx     as Number,
        cy     as Number,
        r      as Number,
        color  as Number) as Void
    {
        var startAngle = 90 - (_animFrame % 6) * 60;
        var endAngle   = startAngle - 120;

        _setAntiAlias(dc, true);
        // Track
        dc.setPenWidth(SPINNER_PW);
        dc.setColor(C_RING_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);

        // Arc
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r,
            Graphics.ARC_CLOCKWISE, startAngle, endAngle);

        dc.setPenWidth(1);
        _setAntiAlias(dc, false);
    }

    // ----------------------------------------------------------
    //  Tick source — three speeds:
    //    150 ms  spinner states, or any alert blink window open
    //    500 ms  any clock running — countdown, count-up or an open
    //            stoppage segment
    //            (keeps the seconds display fresh)
    //   1000 ms  live but idle — keeps the time-of-day line current
    //            and polls the paused-clock reminder
    //   stopped  pre-live idle / error
    // ----------------------------------------------------------
    hidden function _syncTimer() as Void {
        var state = _ble.getState();
        var live  = _ble.isLive();
        var fast  = (state == BLE_SCANNING   ||
                     state == BLE_CONNECTING  ||
                     state == BLE_CONNECTED)  ||
                    (live && (_ble.isAlerting1() || _ble.isAlerting2() ||
                              _ble.isAlerting3()));
        var slow  = (live && (_matchTimer.isRunning()       ||
                              _matchTimer.isCountUpRunning() ||
                              _matchTimer.isStoppageOpen()));

        var period = fast ? 150 : (slow ? 500 : (live ? 1000 : 0));
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
        if (state == BLE_CONNECTING) { return C_ACC_ACTIVE; }
        if (state == BLE_CONNECTED)  { return C_ACC_ACTIVE; }
        if (state == BLE_SUBSCRIBED) { return C_ACC_LIVE;   }
        if (state == BLE_ERROR)      { return C_ACC_ERROR;  }
        return C_ACC_IDLE;
    }

    // ----------------------------------------------------------
    //  Connect-screen text (lowercase).  The live screen has none —
    //  every pixel goes to the timer (BACK opens the settings menu).
    // ----------------------------------------------------------
    hidden function _statusText(state as Number) as String {
        if (state == BLE_IDLE)       { return "tap to scan";        }
        if (state == BLE_SCANNING)   { return "finding relay...";   }
        if (state == BLE_CONNECTING) { return "connecting...";      }
        if (state == BLE_CONNECTED)  { return "enabling notify..."; }
        if (state == BLE_ERROR)      { return _ble.getStatus();     }
        return "";
    }

    // The one input worth knowing about in each state.
    hidden function _hintText(state as Number) as String {
        if (state == BLE_SCANNING   ||
            state == BLE_CONNECTING ||
            state == BLE_CONNECTED)  { return "back = timer only"; }
        if (state == BLE_ERROR)      { return "tap = retry";       }
        return "";
    }

}
