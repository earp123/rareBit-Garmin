import Toybox.Lang;
import Toybox.WatchUi;

// Not used — menu is kept in resources but the app drives everything
// through myGarminAppDelegate (SELECT / BACK / tap).
class myGarminAppMenuDelegate extends WatchUi.MenuInputDelegate {

    function initialize() {
        MenuInputDelegate.initialize();
    }

    function onMenuItem(item as Symbol) as Void {
    }

}
