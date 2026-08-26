// ============================================================
// MatchMenu.mc — settings UI for the match timer.
//
// BACK (or MENU) on the live screen opens a native Menu2:
//   Interval    — MM:SS picker with up/down arrows per field
//   Half        — 1st / 2nd submenu; 2nd bases the count-up at
//                 the interval (counts up from e.g. 45:00)
//                 instead of 00:00
//   Reset Timer
//   Disconnect  — drops the BLE link, back to the scanner
//
// Confirming a picker / submenu selection pops straight back to
// the live screen.
// ============================================================

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

function pushMatchMenu(mt as MatchTimer, ble as BleManager) as Void {
    var menu = new WatchUi.Menu2({:title => "Settings"});
    menu.addItem(new WatchUi.MenuItem("Interval", mt.formatInterval(), :interval, null));
    menu.addItem(new WatchUi.MenuItem("Half", _halfSubLabel(mt), :half, null));
    menu.addItem(new WatchUi.MenuItem("Reset Timer", null, :reset, null));
    if (ble.getState() == BLE_SUBSCRIBED) {
        menu.addItem(new WatchUi.MenuItem("Disconnect", null, :disconnect, null));
    } else {
        // Timer-only / dropped — offer a way back onto the relay.
        menu.addItem(new WatchUi.MenuItem("Rescan", null, :rescan, null));
    }
    if (SIM_TIMER_TEST) {
        // Sim build only — preview the paging-alert flash.
        menu.addItem(new WatchUi.MenuItem("Test Alert 1", null, :simAlert1, null));
        menu.addItem(new WatchUi.MenuItem("Test Alert 2", null, :simAlert2, null));
    }
    // Deliberate exit — BACK on the live screen only ever opens this
    // menu, so this is the app's exit path (no accidental mid-match
    // exits from a stray button press).
    menu.addItem(new WatchUi.MenuItem("Exit App", null, :exitApp, null));
    WatchUi.pushView(menu, new MatchMenuDelegate(mt, ble), WatchUi.SLIDE_UP);
}

function _halfSubLabel(mt as MatchTimer) as String {
    return mt.isSecondHalf()
        ? "2nd — up from " + mt.formatInterval()
        : "1st — up from 00:00";
}

class MatchMenuDelegate extends WatchUi.Menu2InputDelegate {

    hidden var _mt  as MatchTimer;
    hidden var _ble as BleManager;

    function initialize(mt as MatchTimer, ble as BleManager) {
        Menu2InputDelegate.initialize();
        _mt  = mt;
        _ble = ble;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :interval) {
            var view = new IntervalPickerView(
                _mt.getIntervalMinPart(), _mt.getIntervalSecPart());
            WatchUi.pushView(view,
                new IntervalPickerDelegate(_mt, view), WatchUi.SLIDE_LEFT);
        } else if (id == :half) {
            var menu = new WatchUi.Menu2({:title => "Half"});
            menu.addItem(new WatchUi.MenuItem("1st",
                "count up from 00:00", :first, null));
            menu.addItem(new WatchUi.MenuItem("2nd",
                "count up from " + _mt.formatInterval(), :second, null));
            menu.setFocus(_mt.isSecondHalf() ? 1 : 0);
            WatchUi.pushView(menu, new HalfMenuDelegate(_mt), WatchUi.SLIDE_LEFT);
        } else if (id == :reset) {
            _mt.reset();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :disconnect) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            _ble.disconnect();
        } else if (id == :rescan) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            _ble.startScan();
        } else if (id == :exitApp) {
            // AppBase.onStop runs BleManager.teardown() on the way out.
            System.exit();
        } else if (id == :simAlert1 || id == :simAlert2) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            _ble.simulateAlert(id == :simAlert1 ? 1 : 2);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class HalfMenuDelegate extends WatchUi.Menu2InputDelegate {

    hidden var _mt as MatchTimer;

    function initialize(mt as MatchTimer) {
        Menu2InputDelegate.initialize();
        _mt = mt;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        _mt.setSecondHalf(item.getId() == :second);
        // Pop the half submenu and the settings menu — back to live.
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}

// ------------------------------------------------------------
//  Interval picker — MM:SS with up/down arrows per field.
//
//  Touch zones (thirds of the screen height):
//    top third     — increment (left half = minutes, right = seconds)
//    bottom third  — decrement (same left/right split)
//    middle third  — confirm and return to the live screen
//  SELECT also confirms; BACK returns to the settings menu.
//  Swipes (page keys) adjust the minutes.
// ------------------------------------------------------------

const IVP_SEC_STEP = 15;   // seconds field step per arrow tap

class IntervalPickerView extends WatchUi.View {

    var minutes as Number;
    var seconds as Number;

    // Tap-zone boundaries, set from the real drawn geometry each
    // onUpdate() so the hit zones always match the arrows: above the
    // digit band = increment, below = decrement, the band = confirm.
    var zoneTop as Number = 0;
    var zoneBot as Number = 0;

    function initialize(minutes0 as Number, seconds0 as Number) {
        View.initialize();
        minutes = minutes0;
        seconds = seconds0;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        dc.setColor(C_BG, C_BG);
        dc.clear();

        dc.setColor(C_TEXT_SEC, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.16).toNumber(), Graphics.FONT_TINY, "INTERVAL",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // MM : SS — fields flank the colon on the center column.
        var font = Graphics.FONT_NUMBER_MEDIUM;
        var off  = (w * 0.16).toNumber();
        dc.setColor(C_TEXT_PRI, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, font, ":",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx - off, cy, font, minutes.format("%02d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx + off, cy, font, seconds.format("%02d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Up / down arrows above and below each field.
        var digitH = (dc.getFontHeight(font) * CD_VIS_SCALE).toNumber();
        var arrOff = digitH / 2 + (h * 0.07).toNumber();
        var arrW   = (w * 0.045).toNumber();

        // Publish the tap zones: the digit band confirms, everything
        // above/below it (arrows included) adjusts.
        zoneTop = cy - digitH / 2 - 4;
        zoneBot = cy + digitH / 2 + 4;
        dc.setColor(C_TEXT_SEC, Graphics.COLOR_TRANSPARENT);
        _drawArrow(dc, cx - off, cy - arrOff, arrW, true);
        _drawArrow(dc, cx + off, cy - arrOff, arrW, true);
        _drawArrow(dc, cx - off, cy + arrOff, arrW, false);
        _drawArrow(dc, cx + off, cy + arrOff, arrW, false);

        dc.setColor(C_HINT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.84).toNumber(), Graphics.FONT_TINY,
            "tap middle to set",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Solid triangle centered at (x, y); up or down.
    hidden function _drawArrow(
        dc    as Graphics.Dc,
        x     as Number,
        y     as Number,
        halfW as Number,
        up    as Boolean) as Void
    {
        var hh = (halfW * 0.8).toNumber();
        if (up) {
            dc.fillPolygon([[x, y - hh], [x + halfW, y + hh], [x - halfW, y + hh]]);
        } else {
            dc.fillPolygon([[x, y + hh], [x + halfW, y - hh], [x - halfW, y - hh]]);
        }
    }
}

// Raw InputDelegate, NOT BehaviorDelegate: a BehaviorDelegate turns
// touchscreen taps into the select behavior (onSelect) before the raw
// onTap handler ever runs — observed in the simulator, where every
// arrow tap confirmed instead of adjusting.  At the InputDelegate
// level taps arrive with coordinates, untranslated.
class IntervalPickerDelegate extends WatchUi.InputDelegate {

    hidden var _mt   as MatchTimer;
    hidden var _view as IntervalPickerView;

    function initialize(mt as MatchTimer, view as IntervalPickerView) {
        InputDelegate.initialize();
        _mt   = mt;
        _view = view;
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        var xy = clickEvent.getCoordinates();
        var ds = System.getDeviceSettings();
        var isMin = xy[0] < ds.screenWidth / 2;

        // Zone boundaries come from the view's drawn geometry; fall
        // back to screen thirds if a tap somehow beats the first draw.
        var top = (_view.zoneBot > 0) ? _view.zoneTop : ds.screenHeight / 3;
        var bot = (_view.zoneBot > 0) ? _view.zoneBot : ds.screenHeight * 2 / 3;
        System.println("IVP: tap " + xy[0] + "," + xy[1] +
            " zones=[" + top + "," + bot + "]");

        if (xy[1] < top) {
            _bump(isMin, 1);
            return true;
        }
        if (xy[1] > bot) {
            _bump(isMin, -1);
            return true;
        }
        return _confirm();
    }

    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        var k = keyEvent.getKey();
        if (k == WatchUi.KEY_ENTER || k == WatchUi.KEY_START) {
            return _confirm();
        }
        if (k == WatchUi.KEY_ESC) {
            // BACK — cancel, return to the settings menu.
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return true;
        }
        return false;
    }

    // Swallow swipes — adjustment is by tapping the arrows only.
    function onSwipe(swipeEvent as WatchUi.SwipeEvent) as Boolean {
        return true;
    }

    hidden function _bump(isMinutes as Boolean, dir as Number) as Void {
        if (isMinutes) {
            var m = _view.minutes + dir;
            if (m < 0)  { m = 99; }
            if (m > 99) { m = 0;  }
            _view.minutes = m;
        } else {
            var s = _view.seconds + dir * IVP_SEC_STEP;
            if (s < 0)  { s = 60 - IVP_SEC_STEP; }
            if (s > 59) { s = 0; }
            _view.seconds = s;
        }
        // Never allow a 00:00 interval.
        if (_view.minutes == 0 && _view.seconds == 0) {
            _view.seconds = IVP_SEC_STEP;
        }
        WatchUi.requestUpdate();
    }

    hidden function _confirm() as Boolean {
        _mt.setInterval(_view.minutes, _view.seconds);
        // Pop the picker and the settings menu — back to live, ready.
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
