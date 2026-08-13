import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class myGarminAppApp extends Application.AppBase {

    hidden var _bleMgr     as BleManager;
    hidden var _matchTimer as MatchTimer;

    function initialize() {
        AppBase.initialize();
        // Create the BleManager once; it registers the BLE delegate and profile.
        _bleMgr = new BleManager();
        // App-owned so match time survives BLE drops and reconnects.
        _matchTimer = new MatchTimer();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
        // Clean up — stop any scan and unpair any live connection so the
        // GATT interface is never left hanging when the app exits.
        _bleMgr.teardown();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [
            new myGarminAppView(_bleMgr, _matchTimer),
            new myGarminAppDelegate(_bleMgr, _matchTimer)
        ];
    }

    function getBleManager() as BleManager {
        return _bleMgr;
    }

}

function getApp() as myGarminAppApp {
    return Application.getApp() as myGarminAppApp;
}
