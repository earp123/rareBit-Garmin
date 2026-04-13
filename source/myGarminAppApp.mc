import Toybox.Application;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

class myGarminAppApp extends Application.AppBase {

    var _duration as Number = 25 * 60;
    var _remaining as Number = 25 * 60;
    var _elapsed as Number = 0;
    var _running as Boolean = false;
    var _timer as Timer.Timer or Null = null;
    var _ble as BleManager or Null = null;

    function initialize() {
        AppBase.initialize();
        _ble = new BleManager();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
        stopTimer();
    }

    function getBle() as BleManager {
        return _ble as BleManager;
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var ble = _ble as BleManager;
        return [
            new myGarminAppView(ble),
            new myGarminAppDelegate(ble)
        ];
    }

    function toggleTimer() as Void {
        if (_running) {
            stopTimer();
        } else {
            startTimer();
        }
    }

    function startTimer() as Void {
        if (_remaining == 0) {
            _remaining = _duration;
        }
        _running = true;
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1000, true);
        WatchUi.requestUpdate();
    }

    function stopTimer() as Void {
        _running = false;
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
        WatchUi.requestUpdate();
    }

    function onTick() as Void {
        if (_remaining > 0) {
            _remaining -= 1;
            _elapsed += 1;
            WatchUi.requestUpdate();
        } else {
            stopTimer();
        }
    }

    function setDuration(minutes as Number) as Void {
        stopTimer();
        _duration = minutes * 60;
        _remaining = _duration;
        _elapsed = 0;
    }

    function getRemaining() as Number {
        return _remaining;
    }

    function isRunning() as Boolean {
        return _running;
    }

    function getElapsed() as Number {
        return _elapsed;
    }

}

function getApp() as myGarminAppApp {
    return Application.getApp() as myGarminAppApp;
}
