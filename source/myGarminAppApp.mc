import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class myGarminAppApp extends Application.AppBase {

    hidden var _bleMgr as BleManager;

    function initialize() {
        AppBase.initialize();
        // Create the BleManager once; it registers the BLE delegate and profile.
        _bleMgr = new BleManager();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
        // Clean up — stop any in-progress scan when the app exits.
        _bleMgr.stopScan();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [
            new myGarminAppView(_bleMgr),
            new myGarminAppDelegate(_bleMgr)
        ];
    }

    function getBleManager() as BleManager {
        return _bleMgr;
    }

}

function getApp() as myGarminAppApp {
    return Application.getApp() as myGarminAppApp;
}
