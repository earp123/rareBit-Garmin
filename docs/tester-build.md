# Tester Build — Stoppage Timer, Alert 3, UI refresh (3 Oct 2026)

Branch: `feature/tester-build` (from `main`)
Owner: coding agent; Sam runs on-watch testing and ships to testers.
Supersedes `feature/delay-timer` and `feature/short-press-alert` — both
docs live here now, revised. `feature/delay-timer` is not doc-only: it
carries the first Stoppage Timer implementation (`d550d45`), which step 2
starts from. The feature is named **Stoppage**, not Delay (Sam, 3 Oct).

## Order of work

Fail-fast: each step must build and run in the sim before the next.

1. `docs/ui-refresh.md` — palette constants first (everything else draws
   with them), then the live-screen additions, then the connect screen.
2. `docs/stoppage-timer.md` — tap-for-stoppage with the orange `+MM:SS` line.
3. `docs/short-press-alert.md` — Alert 3 parse, buzz, `S` flash label.

Build both flavours after each step: `monkey.jungle` (device) and
`monkey-sim.jungle` (sim, `SIM_TIMER_TEST`). Rebuild every `bin/*.prg`
at the end — the website download table points at them.

## Constraints that hold across all three

- **No new `Timer.Timer`.** The CIQ timer cap already bit once (AR2
  crash, see CHANGELOG). Everything new rides `System.getTimer()` deltas
  and the view's existing tick.
- **Countdown size is untouchable.** Nothing new reserves vertical space
  inside the stack; the ring, link dot and half tag live in the bezel
  margins and the stoppage line reuses the time-of-day slot.
- **No haptic on stoppage start/stop** — a buzz means a page.
- All new state is session-only (no `Application.Properties`), matching
  Interval / Half.

## CHANGELOG (on merge)

Roll the three docs' CHANGELOG notes into one new dated section above
`[Unreleased] — 2026-08-25`; keep that section's open TODOs. Bump nothing
in `manifest.xml`.

## Trello

Card "Feature: Tap for Stoppage time" (Garmin list) carries the checklist
for this whole build. "Short Press GATT Contract" is folded in and gets
archived once this merges.
