# Publish tester builds + screenshots to rarebitofficial.com (13 Oct 2026)

Branch: `feature/publish-builds` (from `main`)
Owner: coding agent on Sam's PC for steps 1–3; Claude (project console) for
steps 4–5; Sam tests on-watch.
Trello: Garmin card "Publish builds to website".

Goal: a Garmin page on rarebitofficial.com (Smart Watch menu, beside Apple
Watch and Bangle.js 2) with one sideloadable `.zip` per supported device and
a handful of simulator screenshots. Decisions (Sam, 13 Oct): all 11 manifest
devices; manual screenshots now; page goes in via the Wix design importer
first, Editor layout as fallback. Builds are hosted as a GitHub Release on
this repo — no separate releases repo.

Fail-fast order: a zip that sideloads and runs on a real watch is the
critical element. Page polish, Downloads-page row and the store link can
all land later.

## What exists

- `bin/rareBitGarmin.prg` is the only **device** build and it is venu2plus
  only. The eleven `bin/rareBitGarmin-sim-*.prg` are the `monkey-sim.jungle`
  flavour (`SIM_TIMER_TEST`): they boot straight into a fake-linked timer and
  are not for the wrist. Leave `bin/` alone; new output goes to `dist/`.
- `docs/web/garmin-page.html` is the page design (download table is a
  placeholder). Claude fills the table once the Media Manager URLs exist.
- Site pattern to match: the Downloads page already serves firmware as
  Media Manager `.zip` archives (`/_files/archives/...zip?dn=PRO_RX_1v8.zip`).
  `.prg` is not an accepted Media Manager type, so every build ships zipped.

## 1. `scripts/build-devices.sh` — eleven signed device builds

Git Bash on Windows (Claude Code's shell here). Behaviour:

1. Parse `manifest.xml` for every `<iq:product id="..."/>` — do not
   hard-code the list; the manifest is the source of truth.
2. Locate the SDK and key once, fail early if either is missing:
   - `monkeyc` from `CIQ_SDK` env var or the current SDK under
     `%APPDATA%/Garmin/ConnectIQ/Sdks/<latest>/bin/` (`monkeyc.bat` on
     Windows).
   - Developer key from `GARMIN_DEV_KEY` env var, else the VS Code setting
     `monkeyC.developerKeyPath`, else the `developer_key` / `*.der` the
     earlier `find` in `.claude/settings.local.json` was looking for. Print
     the resolved path (never commit the key).
3. For each product: `monkeyc -f monkey.jungle -d <id> -y <key> -r
   -o dist/rareBitGarmin-<id>.prg`, then
   `zip -j dist/rareBitGarmin-<id>-tester.1.zip dist/rareBitGarmin-<id>.prg`.
   `-r` (release) is fine for sideload and drops the `.debug.xml`.
4. Stop on the first failed device with a clear message; print a summary
   table (device, prg size) at the end. `dist/` is gitignored except
   nothing — add `dist/` to `.gitignore`.

Smoke test the script by running it to completion: eleven zips, each
containing exactly one `.prg`.

## 2. Screenshots — manual, simulator, one device

Device: **venu3** (454 px round, the best-looking target). Simulator
`File > Save screen capture` gives a 1:1 PNG. Save to
`docs/web/screenshots/<view>-venu3.png`:

| file | build to run | how to get the view |
|---|---|---|
| `connect-venu3.png` | `dist/rareBitGarmin-venu3.prg` (device flavour) | boots to the branded scanning screen; capture inside the 15 s window |
| `live-running-venu3.png` | `bin/rareBitGarmin-sim-venu3.prg` | press SELECT once; green ring, link dot, count-up moving |
| `live-stoppage-venu3.png` | sim | menu → Stoppage Timer on → tap once (dot shows) → tap again → pause; orange `+MM:SS` visible |
| `alert-venu3.png` | sim | menu → Test Alert 1 (or 3); capture during the 3 s flash |
| `menu-venu3.png` | sim | BACK on the live screen |
| `interval-venu3.png` | sim | menu → Interval |

Six is the set; skip one rather than fight the simulator. Commit the PNGs
on this branch.

## 3. GitHub Pages + release

1. Enable Pages from this branch's merge target so Claude can import the
   page: `gh api --method POST repos/earp123/rareBit-Garmin/pages
   -f "source[branch]=main" -f "source[path]=/docs"`. The page will serve at
   `https://earp123.github.io/rareBit-Garmin/web/garmin-page.html` once
   merged. (If Pages is already on, leave it.)
2. After merge to `main`, cut the release from the zips:
   `gh release create GARMIN_v1.0-tester.1 dist/*.zip --title
   "rareBit for Garmin — tester build 1" --notes-file <notes>` with notes
   listing the eleven devices and the sideload line (copy the `.prg` out of
   the zip into `GARMIN/APPS` over USB). Mark it a pre-release.

## 4. Claude — Media Manager, page, importer

- Import the eleven zips and the PNGs from the release / raw GitHub URLs
  into a Media Manager folder `Garmin Builds`.
- Fill the download table in `docs/web/garmin-page.html`: one row per
  device (friendly name, product id, `tester.1`, Media Manager link), drop
  the placeholder note, add a screenshot strip. Push to `main`.
- Run the Wix design importer against the Pages URL. If it does not land
  as a page under Smart Watch, fall back: Sam lays the page out in the
  Editor from the staged assets; Claude supplies the URL list.

## 5. Test and assess

- Sam: sideload one zip's `.prg` onto a real watch via `GARMIN/APPS` and
  confirm it launches and reaches the live screen.
- Sam: from a phone browser, download two zips from the published page.
- Then: add a "rareBit for Garmin" row to the Downloads page (Editor,
  Sam), link the page from the Smart Watch menu, archive the Trello card.

## Constraints

- No change to `source/`, `manifest.xml` or either jungle file. If a device
  fails to build, that is a finding for the CHANGELOG TODOs, not a reason
  to patch source on this branch.
- Never commit the developer key, and keep `dist/` out of git; the release
  is the artifact store.

## CHANGELOG (on merge)

Add a short "Published — tester build 1" entry under the Tester build
section: script added, release tag, page URL. No version bump anywhere.
