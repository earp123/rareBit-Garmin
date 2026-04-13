import Toybox.Lang;
import Toybox.WatchUi;

class TimerDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        getApp().toggleTimer();
        return true;
    }

    function onBack() as Boolean {
        if (!getApp().isRunning()) {
            onMenu();
            return true;
        }
        return false;
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        return onSelect();
    }

    function onMenu() as Boolean {
        var menu = new WatchUi.Menu2({:title => "Duration"});
        var durations = [45, 40, 35, 30, 25, 20, 15] as Array<Number>;
        for (var i = 0; i < durations.size(); i++) {
            var mins = durations[i];
            menu.addItem(new WatchUi.MenuItem(mins + " min", null, mins, {}));
        }
        WatchUi.pushView(menu, new DurationMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

}
