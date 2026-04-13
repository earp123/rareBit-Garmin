import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class TimerView extends WatchUi.View {

    hidden var _ble as BleManager;

    function initialize(ble as BleManager) {
        View.initialize();
        _ble = ble;
    }

    function onLayout(dc as Graphics.Dc) as Void { }

    function onShow() as Void { }

    function onHide() as Void { }

    function onUpdate(dc as Graphics.Dc) as Void {
        var app = getApp();
        var remaining = app.getRemaining();
        var elapsed = app.getElapsed();
        var running = app.isRunning();

        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // getFontHeight() for number fonts returns ~40-50% more than actual visual
        // glyph height due to padding in the font metrics. Scale down to get a
        // value closer to the true rendered height for spacing purposes.
        var mildVisual = (dc.getFontHeight(Graphics.FONT_NUMBER_MILD) * 0.55).toNumber();
        var hotVisual  = (dc.getFontHeight(Graphics.FONT_NUMBER_HOT)  * 0.55).toNumber();
        var gap = 4;

        var countDownY = h / 2;
        var countUpY   = countDownY - hotVisual / 2 - gap - mildVisual / 2;
        var clockY     = countDownY + hotVisual / 2 + gap + mildVisual / 2;
        var dotRowY    = clockY + mildVisual / 2 + gap + dc.getFontHeight(Graphics.FONT_SMALL) / 2;

        // Count-up timer (above, blue)
        var eMins = elapsed / 60;
        var eSecs = elapsed % 60;
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, countUpY, Graphics.FONT_NUMBER_MILD,
            eMins.format("%02d") + ":" + eSecs.format("%02d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Countdown timer (center, white)
        var mins = remaining / 60;
        var secs = remaining % 60;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, countDownY, Graphics.FONT_NUMBER_HOT,
            mins.format("%02d") + ":" + secs.format("%02d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Time of day (below countdown, green, 12h no leading zero)
        var now  = System.getClockTime();
        var hour = now.hour % 12;
        if (hour == 0) { hour = 12; }
        dc.setColor(0x00CC66, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, clockY, Graphics.FONT_NUMBER_MILD,
            hour.format("%d") + ":" + now.min.format("%02d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // D1 / D2 link indicators (below clock)
        _drawD1D2Row(dc, w, cx, dotRowY);

        // State label
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h - 30, Graphics.FONT_TINY,
            running ? "RUNNING" : (remaining == 0 ? "DONE" : "PAUSED"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    hidden function _drawD1D2Row(
        dc as Graphics.Dc,
        w  as Number,
        cx as Number,
        cy as Number) as Void
    {
        var linked1    = _ble.getLinked1();
        var linked2    = _ble.getLinked2();
        var dotR       = 5;
        var dotGap     = 6;   // px between dot edge and label
        var spacing    = w / 4;
        var colorLive  = 0x00CC66;
        var colorDim   = 0x555555;

        // D1 — left of center (dot to the left of the label)
        var d1x = cx - spacing;
        dc.setColor(linked1 ? colorLive : colorDim, Graphics.COLOR_TRANSPARENT);
        if (linked1) {
            dc.fillCircle(d1x - dotGap - dotR, cy, dotR);
        } else {
            dc.drawCircle(d1x - dotGap - dotR, cy, dotR);
        }
        dc.drawText(d1x, cy, Graphics.FONT_SMALL, "AR1",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // D2 — right of center (dot to the right of the label)
        var d2x = cx + spacing;
        dc.setColor(linked2 ? colorLive : colorDim, Graphics.COLOR_TRANSPARENT);
        if (linked2) {
            dc.fillCircle(d2x + dotGap + dotR, cy, dotR);
        } else {
            dc.drawCircle(d2x + dotGap + dotR, cy, dotR);
        }
        dc.drawText(d2x, cy, Graphics.FONT_SMALL, "AR2",
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

}
