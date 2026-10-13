First tester build of rareBit for Garmin — a match timer for officials that
pages you when an assistant referee presses a rareBit flag.

**This is a pre-release for testers.** Please report anything odd to Sam.

## Install (sideload)

1. Download the zip for **your** watch model below. Each build only runs on
   the model it was built for.
2. Unzip it. Inside is a single `rareBitGarmin-<model>.prg`.
3. Plug the watch into a computer over USB and copy the `.prg` into the
   watch's `GARMIN/APPS` folder. (On a Mac, if the watch doesn't show up as
   a drive, use an MTP app such as OpenMTP.)
4. Unplug. rareBit appears in the watch's app list.

| Watch | Download |
|---|---|
| Venu 2 | `rareBitGarmin-venu2-tester.1.zip` |
| Venu 2 Plus | `rareBitGarmin-venu2plus-tester.1.zip` |
| Venu 2S | `rareBitGarmin-venu2s-tester.1.zip` |
| Venu 3 | `rareBitGarmin-venu3-tester.1.zip` |
| Venu 3S | `rareBitGarmin-venu3s-tester.1.zip` |
| Venu 4 41mm | `rareBitGarmin-venu441mm-tester.1.zip` |
| Venu 4 45mm / D2 Air X15 | `rareBitGarmin-venu445mm-tester.1.zip` |
| Venu Sq 2 Music | `rareBitGarmin-venusq2m-tester.1.zip` |
| Venu X1 | `rareBitGarmin-venux1-tester.1.zip` |
| vívoactive 5 | `rareBitGarmin-vivoactive5-tester.1.zip` |
| vívoactive 6 | `rareBitGarmin-vivoactive6-tester.1.zip` |

## What's in this build

- **Match timer** — big countdown (SELECT starts / pauses), a count-up
  running clock, a progress ring, and the time of day.
- **Flag alerts** — connects to a rareBit relay automatically. A long press
  on a flag buzzes and flashes `1` or `2`; a short press flashes `S` (needs a
  relay with short-press support turned on). No relay in range? It drops to
  timer-only after 15 s.
- **Stoppage Timer** (optional, in the settings menu) — tap the screen to
  time injuries, VAR or substitutions without touching the match clock; the
  half's total shows in orange as `+MM:SS`.
- **Settings** — BACK opens the menu: interval, 1st/2nd half, Stoppage
  Timer, reset, disconnect / rescan, exit.

Built from `main` at the commit this release is tagged on.
