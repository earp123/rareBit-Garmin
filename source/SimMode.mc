// ============================================================
// SimMode.mc
//
// Build-flavor flag for simulator UI testing.
//
// The normal device build (monkey.jungle, excludeAnnotations =
// simTest) gets SIM_TIMER_TEST = false.  The simulator UI-test
// build (monkey-sim.jungle, excludeAnnotations = noSimTest) gets
// SIM_TIMER_TEST = true, which makes BleManager boot directly
// into BLE_SUBSCRIBED with both ARs linked so the live
// match-timer screen comes up without real BLE hardware.
//
// NOTE: (:release) / (:debug) are reserved annotations tied to
// the -r build flag — don't use them for this.
// ============================================================

(:noSimTest) const SIM_TIMER_TEST = false;
(:simTest)   const SIM_TIMER_TEST = true;
