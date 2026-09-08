# Task: Delay Timer (tap-to-start stopwatch)

Branch: `feature/delay-timer`
Status: scoped — not started
Owner: coding agent; Sam runs on-watch testing

## Goal

An **optional setting** (default OFF) that turns a screen tap on the live
timer into a way to time a delay — injury, VAR, substitution — **without
touching the countdown or the count-up**. A tap starts a fresh Delay Timer
counting up from 00:00. This is a **separate feature from the count-up**:
the count-up is the running match clock; the Delay Timer is an ad-hoc
stopwatch for interruptions, and the two must never share state.

## Behaviour

Setting: `Delay Timer` — `Off` (default) / `On`. Lives in the settings
menu (`MatchMenu.mc`) as its own item, not a sub-option of Half or Interval.
Session-only, like Interval and Half (no `Application.Properties` yet —
matches the rest of the menu).

With the setting **On**, on the live screen only:

| Input | Countdown / count-up | Delay Timer |
|---|---|---|
| Tap, no delay running | untouched | start new delay from 00:00 |
| Tap, delay running | untouched | stop it; add its elapsed to the delay total |
| SELECT | start / pause as today | untouched |
| Reset Timer (menu) | reset as today | stop + zero current delay **and** total |
| Interval change | reset as today | same as Reset |

With the setting **Off**: tap on the live screen stays inert (the 2026-09-02
stray-touch guard is unchanged).

Tap is gated on `_ble.isLive()` exactly as SELECT is; pre-live tap keeps
its current meaning (start / retry scan).

## Display

- **Current delay** (while running): takes over the time-of-day slot above
  the countdown, amber, same font as the time-of-day line. Time-of-day is
  hidden while a delay runs and returns when it stops.
- **Delay total** (sum of all stopped delays this half): shown as the
  sublabel of the `Delay Timer` menu item, e.g. `On — 03:40 total`. Not
  on the live screen for v1 (keeps the countdown at full size).
- AR alert flash still wins the top slot during its 3 s window; the delay
  keeps counting underneath and redraws afterward.
- No haptic on delay start/stop — a buzz would be mistaken for a page.

## Implementation notes

- `MatchTimer.mc`: add `_delayEnabled`, `_delayRunning`, `_delayStartTick`,
  `_delayTotalMs`; `toggleDelay()`, `getDelayMs()`, `getDelayTotalMs()`,
  `formatDelay()`, `formatDelayTotal()`, `isDelayRunning()`,
  `setDelayEnabled()` / `isDelayEnabled()`. `reset()` and `setInterval()`
  clear all delay state. All `System.getTimer()` deltas — **no new
  `Timer.Timer`** (CIQ timer cap; see AR2 crash in CHANGELOG).
- `myGarminAppDelegate.mc` `onTap()`: `if live && delayEnabled →
  toggleDelay() + requestUpdate(); return true`.
- `myGarminAppView.mc`: the 1 s idle tick already refreshes the digits;
  while a delay runs the top line draws `formatDelay()` instead of the
  clock. Note the tick only runs when something is animating — confirm a
  running delay keeps the 500 ms / 1 s tick alive.
- `MatchMenu.mc`: `Delay Timer` item → two-entry submenu (`Off` / `On`),
  focus on current, pop-to-live on select (same pattern as Half).
- Sim build: exercise via `monkey-sim.jungle` — taps are trivial to
  generate in the simulator.

## Test (Sam, on-watch)

1. Setting Off: tap on live screen does nothing (unchanged).
2. Setting On, match running: tap → amber delay counts up above the
   countdown; countdown and count-up keep moving. Tap → delay stops,
   time-of-day returns, menu sublabel shows the total.
3. Repeat 2 three times; total is the sum. Reset Timer zeroes everything.
4. Page an AR mid-delay: flash shows, delay continues correctly after.
5. Sleeve / raindrop check: with the setting On, a stray touch starts a
   delay but never touches the clock (accepted trade-off of the setting).

## Decisions (flagged)

- **Second tap stops the delay and banks it into a total.** Alternative
  read of the spec: every tap simply restarts from 00:00 with no stop and
  no total. Stop-and-bank chosen because the total is what a referee
  needs for added time. Easy to switch — say the word.
- **Total not shown on the live screen** for v1. Countdown size is the
  app's top priority; add it later if the sublabel proves too hidden.
- **Setting is session-only** for parity with the existing menu. If
  persistence is wanted, do all three (Interval, Half, Delay) in one pass.

## CHANGELOG

Add under `[Unreleased] › Added`: **Delay Timer** — optional tap-to-start
stopwatch for interruptions; separate from the count-up; total per half in
the menu sublabel.
