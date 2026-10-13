#!/usr/bin/env bash
# ============================================================
# build-devices.sh — one signed, sideloadable DEVICE build per
# product in manifest.xml, each zipped for the website.
#
#   scripts/build-devices.sh [tag]        (tag defaults to tester.1)
#
# Output (dist/ is gitignored — the GitHub Release is the artifact
# store):
#   dist/rareBitGarmin-<id>.prg
#   dist/rareBitGarmin-<id>-<tag>.zip     (exactly one .prg inside)
#
# Device flavour only (monkey.jungle, release -r).  The bin/*-sim-*
# builds are the SIM_TIMER_TEST flavour — they fake a linked relay and
# must never reach a wrist.
#
# Written for Git Bash on Windows (also fine on macOS / Linux).
#   SDK:  $CIQ_SDK (SDK root or its bin/), else the SDK manager's
#         current-sdk.cfg, else the newest SDK under
#         $APPDATA/Garmin/ConnectIQ/Sdks/.
#   Key:  $GARMIN_DEV_KEY, else VS Code's monkeyC.developerKeyPath,
#         else the first developer_key / *.der within 4 levels of $HOME.
#         Never commit the key.
# ============================================================

set -euo pipefail

TAG="${1:-tester.1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
cd "$ROOT"

die() { echo "build-devices: $*" >&2; exit 1; }

# Windows paths (C:\...) → forward slashes, which both Git Bash and
# monkeyc.bat accept.
fwd() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"
    else printf '%s' "$1" | tr '\134' '/'; fi
}

# ── Products: manifest.xml is the source of truth ───────────
[ -f manifest.xml ] || die "manifest.xml not found in $ROOT"
PRODUCTS=()
while IFS= read -r id; do PRODUCTS+=("$id"); done < <(
    grep -o '<iq:product id="[^"]*"' manifest.xml | sed 's/.*id="\([^"]*\)"/\1/')
[ "${#PRODUCTS[@]}" -gt 0 ] || die "no <iq:product id=...> entries in manifest.xml"

# ── SDK: locate monkeyc once ────────────────────────────────
find_monkeyc() {   # $1 = an SDK root or its bin/ directory
    local d; d="$(fwd "$1")"; d="${d%/}"
    for c in "$d/bin/monkeyc.bat" "$d/bin/monkeyc" "$d/monkeyc.bat" "$d/monkeyc"; do
        [ -f "$c" ] && { printf '%s' "$c"; return 0; }
    done
    return 1
}
CIQ_HOME="$(fwd "${APPDATA:-$HOME/.Garmin}")/Garmin/ConnectIQ"
MONKEYC=""
if [ -n "${CIQ_SDK:-}" ]; then
    MONKEYC="$(find_monkeyc "$CIQ_SDK")" || die "CIQ_SDK=$CIQ_SDK has no bin/monkeyc"
elif [ -f "$CIQ_HOME/current-sdk.cfg" ]; then
    MONKEYC="$(find_monkeyc "$(tr -d '\r\n' < "$CIQ_HOME/current-sdk.cfg")")" || true
fi
if [ -z "$MONKEYC" ] && [ -d "$CIQ_HOME/Sdks" ]; then
    latest="$(ls -1d "$CIQ_HOME"/Sdks/*/ 2>/dev/null | sort | tail -1)"
    [ -n "$latest" ] && MONKEYC="$(find_monkeyc "$latest")" || true
fi
[ -n "$MONKEYC" ] || die "Connect IQ SDK not found — set CIQ_SDK to the SDK root"

# ── Developer key ───────────────────────────────────────────
KEY=""
if [ -n "${GARMIN_DEV_KEY:-}" ]; then
    KEY="$(fwd "$GARMIN_DEV_KEY")"
    [ -f "$KEY" ] || die "GARMIN_DEV_KEY=$GARMIN_DEV_KEY does not exist"
else
    vscode="$(fwd "${APPDATA:-$HOME/.config}")/Code/User/settings.json"
    if [ -f "$vscode" ]; then
        k="$(sed -n 's/.*"monkeyC.developerKeyPath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$vscode" | head -1)"
        k="$(printf '%s' "$k" | tr '\134' '/' | sed 's#//*#/#g')"   # JSON-escaped backslashes -> single /
        [ -n "$k" ] && [ -f "$(fwd "$k")" ] && KEY="$(fwd "$k")"
    fi
    if [ -z "$KEY" ]; then
        KEY="$(find "$HOME" -maxdepth 4 \( -name developer_key -o -name '*.der' \) \
                   -type f 2>/dev/null | head -1)"
        [ -n "$KEY" ] && KEY="$(fwd "$KEY")"
    fi
fi
[ -n "$KEY" ] || die "developer key not found — set GARMIN_DEV_KEY"

# ── Zipper: zip -j, else Python's zipfile, else PowerShell ─────
zip_one() {   # $1 = zip to create, $2 = the single file to put at its root
    rm -f "$1"
    if command -v zip >/dev/null 2>&1; then
        zip -j -q "$1" "$2"
    elif command -v python >/dev/null 2>&1 && python -c 'import zipfile' 2>/dev/null; then
        # The zipfile CLI stores top-level files under their basename (= -j).
        python -m zipfile -c "$1" "$2"
    elif command -v powershell.exe >/dev/null 2>&1; then
        powershell.exe -NoProfile -Command \
            "Compress-Archive -LiteralPath '$(fwd "$2")' -DestinationPath '$(fwd "$1")' -Force"
    else
        die "no zip tool (zip, python or powershell) found"
    fi
}

echo "SDK:      $MONKEYC"
echo "Key:      $KEY"
echo "Tag:      $TAG"
echo "Products: ${PRODUCTS[*]} (${#PRODUCTS[@]})"
echo

# Fresh output for this tag — no stale builds from a device that has
# since left the manifest.
mkdir -p "$DIST"
rm -f "$DIST"/rareBitGarmin-*.prg "$DIST"/rareBitGarmin-*-"$TAG".zip

for id in "${PRODUCTS[@]}"; do
    prg="$DIST/rareBitGarmin-$id.prg"
    zip="$DIST/rareBitGarmin-$id-$TAG.zip"
    printf '%-14s ' "$id"
    if ! log="$("$MONKEYC" -f monkey.jungle -d "$id" -y "$KEY" -r -o "$prg" 2>&1)" \
       || [ ! -s "$prg" ]; then
        echo "FAILED"
        echo "$log" | tail -20 >&2
        die "build failed for $id — stopping (see output above)"
    fi
    zip_one "$zip" "$prg"
    echo "ok"
done

echo
printf '%-14s %10s %10s\n' "device" "prg bytes" "zip bytes"
for id in "${PRODUCTS[@]}"; do
    printf '%-14s %10s %10s\n' "$id" \
        "$(wc -c < "$DIST/rareBitGarmin-$id.prg" | tr -d ' ')" \
        "$(wc -c < "$DIST/rareBitGarmin-$id-$TAG.zip" | tr -d ' ')"
done
echo
echo "${#PRODUCTS[@]} device builds in $(fwd "$DIST")"
