# Short Press Alert — Alert 3 on the Garmin (13 Sep 2026)

Scope: `rareBit-Garmin` — `source/BleManager.mc`, `source/myGarminAppView.mc`.
Contract owner: `rareBit-Flags-Receivers/docs/short-press-alert.md`
(`common/include/uuids.h`, `RELAY_NOTIFY_*`).

## State today

`onCharacteristicChanged()` reads the relay notify byte as bits 7/6 = AR1/AR2
linked and bits 1–0 = a two-bit type: `NOTIFY_LINKED` 0, `NOTIFY_ALERT_1` 1,
`NOTIFY_ALERT_2` 2, `NOTIFY_UNUSED` 3. Type 3 falls through every branch — a new
relay build sending Alert 3 shows nothing on the watch.

## Contract

Firmware (RXRLY and rareBit-Relay, `feature/short-press-alert`) now sends type
**3 = Alert 3**: a short press from either flag, delivered only when the relay's
own short-press setting is on. It does not say which flag pressed; slot alerts
(1/2) are unchanged and still mean long press by slot. The link bits arrive with
every notify as before.

## Change

1. `BleManager.mc`: rename `NOTIFY_UNUSED` → `NOTIFY_ALERT_3 = 3` (comment: short
   press, either AR). Add `_alert3Until`, clear it in `_clearSession()`, expose
   `isAlerting3()` via `_alertOpen()`.
2. `onCharacteristicChanged()`: `if (_notifType == NOTIFY_ALERT_3) { _alert3Until =
   System.getTimer() + ALERT_BLINK_MS; _buzzAlert3(); }`. Log line unchanged
   (already prints `type=`).
3. `_buzzAlert3()`: one `Attention.vibrate` call, three quick taps with the linked
   double-tap's timing — `(100, 120)`, `(0, 100)`, `(100, 120)`, `(0, 100)`,
   `(100, 120)` (~0.56 s; shortened from 250 ms pulses at Sam's request, 3 Oct).
   Distinct from AR1's single 2 s buzz, AR2's four 500 ms buzzes and the linked
   double-tap (by count); zero timers, same reason as `_buzzAlert2`. Close to the
   pause reminder's three 80 ms taps — check on the wrist.
4. `myGarminAppView.mc`, `_drawLiveScreen()`: include `a3 = _ble.isAlerting3()` in
   the flash gate. Label string becomes `"S"` when only a3 is open; when a slot
   alert overlaps, append it — `"1 S"`, `"2 S"`, `"1 2 S"`. Same icon, same amber,
   same 300 ms phases. `_syncTimer()`: add `isAlerting3()` to the fast-tick
   condition or the flash never animates.
5. `SIM_TIMER_TEST`: extend `simulateAlert(arNum)` to accept 3 so the flash and
   label can be checked in the simulator.

## Test (Sam — watch on a relay running `feature/short-press-alert`, relay bit 0 on)

1. Link two flags → double-tap on each `0x80` / `0xC0`, no flash.
2. Short press A → 3-pulse buzz, icon + `S` flashes 3 s. Short press B → identical.
3. Long press A → 2 s buzz + `1`; long press B → 4 buzzes + `2`. Unchanged.
4. Short press right after a long press → `1 S` while both windows overlap.
5. Relay bit 0 off → a short press arrives as `0xC1` / `0xC2` and behaves as a slot
   alert. Old watch build on the new relay → nothing on `0xC3` (reserved path).

## Assess

- `_notifLocked` gate applies to type 3 like any alert: a stacked `0xC3` inside the
  3 s post-subscribe window is dropped by design.
- CHANGELOG on merge: notify byte table gains type 3; note the `S` label and buzz.
- Connect IQ Store submission (existing card) should ship this so store users see
  short presses from day one.
