#!/usr/bin/env bash
# Install LightCraft (latest official Linux release) for the current user. No sudo needed.
#
#   ./install-lightcraft.sh              install or update to the latest release
#   ./install-lightcraft.sh 0.5.0        install a specific version
#   ./install-lightcraft.sh --uninstall  remove it (your library and settings are kept)
#
# Installs under ~/.local (override with PREFIX=/some/dir).
# The messages are addressed to Terry; run with FRIEND=SomeoneElse to change the name.
set -euo pipefail

APP=lightcraft
NAME=LightCraft
APP_ID=ai.storyteller.$APP
REPO=storytold/$APP
FRIEND="${FRIEND:-Terry}"
PREFIX="${PREFIX:-$HOME/.local}"
OPT="$PREFIX/opt/$APP"
BIN="$PREFIX/bin"
SHARE="$PREFIX/share"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

# Keep the window open when the script was started by double-clicking it.
pause_before_close() {
  if [ -t 0 ] && [ -t 1 ]; then
    read -r -p "Press Enter to close this window. " _ || true
  fi
}

die() {
  printf '\n\033[1mSorry %s, the %s installation stopped.\033[0m\n' "$FRIEND" "$NAME" >&2
  printf 'Reason: %s\n' "$*" >&2
  printf 'Nothing on the laptop is broken. Check the internet connection and run this again;\n' >&2
  printf 'if it keeps happening, send a photo of this message to whoever set this up for you.\n' >&2
  pause_before_close
  exit 1
}

# Run a command in the background and keep one line on screen moving until it finishes, so it is
# clear the install has not frozen. Given a file and its expected size, it shows progress too.
#   keep_alive "message" [file total_bytes] -- command...
keep_alive() {
  local msg=$1 file="" total=0
  shift
  if [ "$1" != "--" ]; then
    file=$1
    total=$2
    shift 2
  fi
  shift
  "$@" &
  local pid=$! start=$SECONDS i=0 frames='|/-\' last=-1 t detail have
  while kill -0 "$pid" 2>/dev/null; do
    t=$((SECONDS - start))
    detail=$(printf '%d:%02d' $((t / 60)) $((t % 60)))
    if [ -n "$file" ] && [ -f "$file" ]; then
      have=$(stat -c %s "$file" 2>/dev/null || echo 0)
      if [ "$total" -gt 0 ]; then
        detail="$((have * 100 / total))% ($((have >> 20)) of $((total >> 20)) MB), $detail"
      else
        detail="$((have >> 20)) MB, $detail"
      fi
    fi
    if [ -t 1 ]; then
      printf '\r\033[K  %s %s: %s. Not frozen, still working!' "${frames:i++%4:1}" "$msg" "$detail"
    elif [ $((t / 15)) -ne "$last" ]; then
      last=$((t / 15))
      printf '  %s: %s. Not frozen, still working!\n' "$msg" "$detail"
    fi
    sleep 0.3
  done
  if [ -t 1 ]; then printf '\r\033[K'; fi
  wait "$pid"
}

refresh_caches() {
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$SHARE/applications" || true
  command -v update-mime-database >/dev/null 2>&1 && update-mime-database "$SHARE/mime" >/dev/null 2>&1 || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t -f "$SHARE/icons/hicolor" 2>/dev/null || true
}

remove_files() {
  rm -rf "$OPT"
  rm -f "$BIN/$APP" "$BIN/$APP-cli"
  rm -f "$SHARE/applications/$APP_ID.desktop" "$SHARE/mime/packages/$APP_ID.xml" "$SHARE/metainfo/$APP_ID.metainfo.xml"
  [ -d "$SHARE/icons/hicolor" ] && find "$SHARE/icons/hicolor" -name "$APP_ID.*" -delete || true
}

if [ "${1:-}" = "--uninstall" ]; then
  say "Removing $NAME from $PREFIX"
  remove_files
  refresh_caches
  say "$NAME removed."
  exit 0
fi

# Stop the laptop going to sleep while the install runs (also with the lid closed, where the
# system allows it). The script restarts itself once under systemd-inhibit.
if [ -z "${CRAFT_AWAKE:-}" ] && command -v systemd-inhibit >/dev/null 2>&1; then
  for what in sleep:idle:handle-lid-switch sleep:idle; do
    if systemd-inhibit --what="$what" true 2>/dev/null; then
      CRAFT_AWAKE=$what exec systemd-inhibit --what="$what" --who="$NAME installer" --why="Installing $NAME" bash "$0" "$@"
    fi
  done
fi

printf '\n\033[1mDon'"'"'t worry %s, your %s installation has begun!\033[0m\n' "$FRIEND" "$NAME"
echo "  - It takes a few minutes, depending on the internet speed."
echo "  - A moving line below shows it is still working. It is NOT frozen."
echo "  - Please don't turn off the laptop or close this window until it says it is finished."
case "${CRAFT_AWAKE:-}" in
  *lid*) echo "  - The laptop will stay awake by itself until this is done, even with the lid closed." ;;
  ?*) echo "  - The laptop will stay awake by itself until this is done. Please keep the lid open." ;;
  *) echo "  - Please keep the lid open so the laptop doesn't go to sleep." ;;
esac
echo "  - Keep the charger plugged in if you can."
echo

[ "$(uname -s)" = "Linux" ] || die "this script is for Linux"
case "$(uname -m)" in
  x86_64 | amd64) ARCH=x86_64 ;;
  aarch64 | arm64) ARCH=aarch64 ;;
  *) die "unsupported CPU architecture: $(uname -m)" ;;
esac
for tool in curl tar sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || die "'$tool' is required but not installed"
done

VERSION="${1:-}"
VERSION="${VERSION#v}"
if [ -z "$VERSION" ]; then
  say "Step 1 of 4: finding the newest $NAME"
  latest=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest") ||
    die "could not reach github.com (is the internet connected?)"
  VERSION="${latest##*/v}"
  [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]] || die "could not work out the latest version (got '$latest')"
else
  say "Step 1 of 4: using $NAME $VERSION"
fi

ASSET="$APP-$VERSION-linux-$ARCH.tar.gz"
BASE="https://github.com/$REPO/releases/download/v$VERSION"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

say "Step 2 of 4: downloading $NAME $VERSION (the longest step)"
TOTAL=$(curl -fsSLI "$BASE/$ASSET" 2>/dev/null | awk 'tolower($1) == "content-length:" { n = $2 } END { print n + 0 }') || TOTAL=0
keep_alive "Downloading" "$TMP/$ASSET" "${TOTAL:-0}" -- curl -fsSL --retry 3 -o "$TMP/$ASSET" "$BASE/$ASSET" ||
  die "the download failed ($BASE/$ASSET)"

say "Step 3 of 4: checking the download is complete and genuine"
curl -fsSL -o "$TMP/SHA256SUMS.txt" "$BASE/SHA256SUMS.txt" || die "could not download SHA256SUMS.txt"
expected=$(awk -v f="$ASSET" '{ n = $2; sub(/^\*/, "", n); if (n == f) print $1 }' "$TMP/SHA256SUMS.txt")
[ -n "$expected" ] || die "$ASSET is not listed in SHA256SUMS.txt"
actual=$(sha256sum "$TMP/$ASSET" | awk '{ print $1 }')
[ "$expected" = "$actual" ] || die "checksum mismatch for $ASSET (expected $expected, got $actual)"

say "Step 4 of 4: installing $NAME"
mkdir -p "$TMP/x"
keep_alive "Unpacking" -- tar -xzf "$TMP/$ASSET" -C "$TMP/x" --strip-components=1 || die "could not unpack $ASSET"
[ -x "$TMP/x/bin/$APP" ] || die "unexpected archive layout: bin/$APP not found"
remove_files
mkdir -p "$PREFIX/opt" "$BIN" "$SHARE/applications" "$SHARE/mime/packages" "$SHARE/icons"
mv "$TMP/x" "$OPT"

ln -sf "$OPT/bin/$APP" "$BIN/$APP"
[ -x "$OPT/bin/$APP-cli" ] && ln -sf "$OPT/bin/$APP-cli" "$BIN/$APP-cli"

# The launcher entry points at the full path, so it works even when ~/.local/bin is not on PATH.
sed "s|^Exec=$APP|Exec=$OPT/bin/$APP|" "$OPT/share/applications/$APP_ID.desktop" >"$SHARE/applications/$APP_ID.desktop"
[ -f "$OPT/share/mime/packages/$APP_ID.xml" ] && cp "$OPT/share/mime/packages/$APP_ID.xml" "$SHARE/mime/packages/"
[ -d "$OPT/share/icons/hicolor" ] && cp -R "$OPT/share/icons/hicolor" "$SHARE/icons/"
refresh_caches

printf '\n\033[1mAll done, %s! %s %s is installed.\033[0m\n' "$FRIEND" "$NAME" "$VERSION"
echo "  - Open it from your app launcher: search for \"$NAME\"."
echo "  - It is now safe to close this window, close the lid or turn off the laptop."
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "  - (For terminal use: $BIN is not on your PATH; the full path is $BIN/$APP)" ;;
esac
if command -v notify-send >/dev/null 2>&1; then
  notify-send -i "$APP_ID" "$NAME is installed" "All done, $FRIEND! You can open it from your app launcher." 2>/dev/null || true
fi
pause_before_close
