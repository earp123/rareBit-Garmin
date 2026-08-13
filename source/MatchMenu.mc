// ============================================================
// MatchMenu.mc — settings UI for the match timer.
//
// MENU on the live screen opens a native Menu2 (renders well on
// round screens):
//   Reset Timer
//   Half      — toggles the count-up base: 1st = 00:00,
//               2nd = the selected interval (e.g. 45:00)
//   Interval  — presets 5..45 min in 5-min steps, plus a
//               Custom picker for any 1-99 min value
//
// Selecting an interval (preset or custom) resets the timer and
// returns straight to the live screen.
// ============================================================

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

function pushMatchMenu(mt as MatchTimer) as Void {
    var menu = new WatchUi.Menu2({:title => "Match"});
    menu.addItem(new WatchUi.MenuItem("Reset Timer", null, :reset, null));
    menu.addItem(new WatchUi.MenuItem("Half", _halfSubLabel(mt), :half, null));
    menu.addItem(new WatchUi.MenuItem("Interval",
        mt.getIntervalMin().toString() + " min", :interval, null));
    WatchUi.pushView(menu, new MatchMenuDelegate(mt), WatchUi.SLIDE_UP);
}

function _halfSubLabel(mt as MatchTimer) as String {
    return mt.isSecondHalf()
        ? "2nd — up from " + mt.getIntervalMin().format("%02d") + ":00"
        : "1st — up from 00:00";
}

class MatchMenuDelegate extends WatchUi.Menu2InputDelegate {

    hidden var _mt as MatchTimer;

    function initialize(mt as MatchTimer) {
        Menu2InputDelegate.initialize();
        _mt = mt;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :reset) {
            _mt.reset();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :half) {
            _mt.setSecondHalf(!_mt.isSecondHalf());
            item.setSubLabel(_halfSubLabel(_mt));
            WatchUi.requestUpdate();
        } else if (id == :interval) {
            var menu = new WatchUi.Menu2({:title => "Interval"});
            for (var m = 5; m <= 45; m += 5) {
                menu.addItem(new WatchUi.MenuItem(m.toString() + " min", null, m, null));
            }
            menu.addItem(new WatchUi.MenuItem("Custom", null, :custom, null));
            WatchUi.pushView(menu, new IntervalMenuDelegate(_mt), WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class IntervalMenuDelegate extends WatchUi.Menu2InputDelegate {

    hidden var _mt as MatchTimer;

    function initialize(mt as MatchTimer) {
        Menu2InputDelegate.initialize();
        _mt = mt;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :custom) {
            var view = new CustomIntervalView(_mt.getIntervalMin());
            WatchUi.pushView(view,
                new CustomIntervalDelegate(_mt, view), WatchUi.SLIDE_LEFT);
        } else {
            _mt.setIntervalMin(id as Number);
            // Pop the interval menu and the settings menu — land on
            // the live screen ready to start.
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}

// ------------------------------------------------------------
//  Custom interval picker — swipe up/down (or page buttons) to
//  adjust minutes, SELECT/tap to set, BACK to cancel.
// ------------------------------------------------------------

class CustomIntervalView extends WatchUi.View {

    var minutes as Number;

    function initialize(initial as Number) {
        View.initialize();
        minutes = initial;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        dc.setColor(C_BG, C_BG);
        dc.clear();

        // All anchors sit near the vertical center column, so the
        // layout stays inside a round screen's usable area.
        dc.setColor(C_TEXT_SEC, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.20).toNumber(), Graphics.FONT_TINY,
            "CUSTOM INTERVAL",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(C_TEXT_PRI, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.45).toNumber(), Graphics.FONT_NUMBER_MEDIUM,
            minutes.toString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(C_TEXT_SEC, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.64).toNumber(), Graphics.FONT_TINY, "min",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(C_HINT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.82).toNumber(), Graphics.FONT_TINY,
            "swipe to adjust — tap to set",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class CustomIntervalDelegate extends WatchUi.BehaviorDelegate {

    hidden var _mt   as MatchTimer;
    hidden var _view as CustomIntervalView;

    function initialize(mt as MatchTimer, view as CustomIntervalView) {
        BehaviorDelegate.initialize();
        _mt   = mt;
        _view = view;
    }

    function onNextPage() as Boolean { _bump(1);  return true; }
    function onPreviousPage() as Boolean { _bump(-1); return true; }

    hidden function _bump(delta as Number) as Void {
        var v = _view.minutes + delta;
        if (v < 1)  { v = 1;  }
        if (v > 99) { v = 99; }
        _view.minutes = v;
        WatchUi.requestUpdate();
    }

    function onSelect() as Boolean { return _confirm(); }

    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        return _confirm();
    }

    hidden function _confirm() as Boolean {
        _mt.setIntervalMin(_view.minutes);
        // Pop picker, interval menu, and settings menu — back to live.
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        return true;
    }
}
