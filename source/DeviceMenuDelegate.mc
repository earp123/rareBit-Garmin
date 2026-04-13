import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.WatchUi;

class DeviceMenuDelegate extends WatchUi.Menu2InputDelegate {

    hidden var _ble as BleManager;

    function initialize(ble as BleManager) {
        Menu2InputDelegate.initialize();
        _ble = ble;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var result = item.getId() as BluetoothLowEnergy.ScanResult;
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        _ble.connectToResult(result);
    }

    function onBack() as Void {
        _ble.stopScan();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

}
