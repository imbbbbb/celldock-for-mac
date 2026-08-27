#!/bin/zsh
# Builds a release CellDock.app and wraps it in a distributable .dmg.
#
# This exists alongside build_app.sh rather than replacing it. That script
# produces the official archive and deliberately refuses ad-hoc signing, since
# a real archive needs signer pinning and Keychain continuity. It also builds
# the VoWiFi runtime, which requires a Go toolchain. Neither applies to a fork
# built for personal use, so this script takes the same assembly and signing
# order that build_and_run.sh already proves works, but in release
# configuration and ending in a disk image.
#
# Without a Developer ID certificate the result is ad-hoc signed. It runs fine
# locally, but once the .dmg travels over the network macOS quarantines it and
# refuses to open the app — see the README written into the image.

set -euo pipefail

APP_NAME="CellDock"
BUNDLE_ID="app.celldock.mac"
ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$ROOT_DIR/outputs"
STAGE_APP_DIR="$ROOT_DIR/.build/release-app"
APP_BUNDLE="$STAGE_APP_DIR/CellDock.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/CellDock"
HELPER_DIR="$APP_CONTENTS/Library/PrivilegedHelperTools"
DAEMON_DIR="$APP_CONTENTS/Library/LaunchDaemons"
WORKSPACE_HOME="$ROOT_DIR/.build/home"
WORKSPACE_CACHE="$ROOT_DIR/.build/caches"

VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT_DIR/Resources/Info.plist")"
BUILD_VERSION="$(plutil -extract CFBundleVersion raw "$ROOT_DIR/Resources/Info.plist")"
DISPLAY_NAME="$(plutil -extract CFBundleDisplayName raw "$ROOT_DIR/Resources/Info.plist")"
DMG_PATH="$OUTPUT_DIR/CellDock-$VERSION-arm64.dmg"

SIGN_IDENTITY="${CELLDOCK_CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null |
      awk -F'"' '/"Developer ID Application:/ { print $2; exit }'
  )"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null |
      awk -F'"' '/"Apple Development:/ { print $2; exit }'
  )"
fi
ADHOC=false
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
  ADHOC=true
fi

print "=== CellDock $VERSION (build $BUILD_VERSION) ==="
if [[ "$ADHOC" == true ]]; then
  print "Signing   : ad-hoc (no certificate found)"
  print "            Recipients will need to clear the quarantine flag."
else
  print "Signing   : $SIGN_IDENTITY"
fi
print "Output    : $DMG_PATH"
print ""

mkdir -p "$WORKSPACE_HOME" "$WORKSPACE_CACHE/clang" "$WORKSPACE_CACHE/swiftpm" "$OUTPUT_DIR"
export HOME="$WORKSPACE_HOME"
export XDG_CACHE_HOME="$WORKSPACE_CACHE"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$WORKSPACE_CACHE/clang}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$WORKSPACE_CACHE/swiftpm}"

cd "$ROOT_DIR"
print "=== Building (release) ==="
xcrun swift build -c release --disable-sandbox -Xswiftc -disable-sandbox
BIN_DIR="$(
  xcrun swift build -c release --disable-sandbox -Xswiftc -disable-sandbox --show-bin-path
)"

print "=== Assembling bundle ==="
/bin/rm -rf -- "$STAGE_APP_DIR"
mkdir -p \
  "$APP_MACOS" \
  "$APP_RESOURCES" \
  "$APP_CONTENTS/Frameworks" \
  "$HELPER_DIR" \
  "$DAEMON_DIR"

cp "$ROOT_DIR/Resources/Info.plist" "$APP_CONTENTS/Info.plist"
cp "$BIN_DIR/CellDock" "$APP_BINARY"
cp "$BIN_DIR/CellDockNetworkHelper" "$HELPER_DIR/CellDockNetworkHelper"
cp "$ROOT_DIR/Resources/app.celldock.mac.network.helper.plist" \
  "$DAEMON_DIR/app.celldock.mac.network.helper.plist"
cp "$ROOT_DIR/Resources/CellDock.icns" "$APP_RESOURCES/CellDock.icns"
cp "$ROOT_DIR/Resources/sim.svg" "$APP_RESOURCES/sim.svg"
cp "$ROOT_DIR/Resources/sim1.svg" "$APP_RESOURCES/sim1.svg"
cp "$ROOT_DIR/Resources/celldock-module-vertical.svg" \
  "$APP_RESOURCES/celldock-module-vertical.svg"
cp -R "$ROOT_DIR/Resources/Localization/"*.lproj "$APP_RESOURCES/"
mkdir -p "$APP_RESOURCES/Sounds"
cp "$ROOT_DIR/Resources/Sounds/bleeps.wav" "$APP_RESOURCES/Sounds/bleeps.wav"
cp "$ROOT_DIR/Resources/Sounds/ring.mp3" "$APP_RESOURCES/Sounds/ring.mp3"

# CellDock links Sparkle and its rpath points at Contents/Frameworks. Without
# the embedded framework dyld terminates the process the instant it launches.
SPARKLE_FRAMEWORK_SOURCE="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$SPARKLE_FRAMEWORK_SOURCE" ]] || {
  print -u2 "SwiftPM did not resolve the Sparkle framework: $SPARKLE_FRAMEWORK_SOURCE"
  exit 1
}
ditto "$SPARKLE_FRAMEWORK_SOURCE" "$APP_CONTENTS/Frameworks/Sparkle.framework"

if [[ -d "$ROOT_DIR/Resources/ModuleVoice" ]]; then
  xcrun swift "$ROOT_DIR/scripts/build_module_voice_payload.swift" \
    "$ROOT_DIR/Resources/ModuleVoice" \
    "$APP_RESOURCES/ModuleVoice.payload" >/dev/null
fi

print "=== Signing (inside-out) ==="
xattr -cr "$APP_BUNDLE"
SPARKLE_VERSION="$APP_CONTENTS/Frameworks/Sparkle.framework/Versions/B"
[[ ! -e "$SPARKLE_VERSION/XPCServices/Installer.xpc" ]] || \
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none \
    "$SPARKLE_VERSION/XPCServices/Installer.xpc"
[[ ! -e "$SPARKLE_VERSION/XPCServices/Downloader.xpc" ]] || \
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none \
    --preserve-metadata=entitlements \
    "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
[[ ! -e "$SPARKLE_VERSION/Autoupdate" ]] || \
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none \
    "$SPARKLE_VERSION/Autoupdate"
[[ ! -e "$SPARKLE_VERSION/Updater.app" ]] || \
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none \
    "$SPARKLE_VERSION/Updater.app"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none \
  "$APP_CONTENTS/Frameworks/Sparkle.framework"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none \
  --identifier app.celldock.mac.network.helper \
  "$HELPER_DIR/CellDockNetworkHelper"
# Entitlements go on the app itself: Hardened Runtime denies the microphone and
# the address book outright unless they are declared, and the request never even
# reaches the user.
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none \
  --entitlements "$ROOT_DIR/Resources/CellDock.entitlements" \
  --identifier "$BUNDLE_ID" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

print "=== Building disk image ==="
STAGING="$(mktemp -d /tmp/CellDock-dmg.XXXXXX)"
trap '/bin/rm -rf -- "$STAGING"' EXIT
ditto "$APP_BUNDLE" "$STAGING/$DISPLAY_NAME.app"
ln -s /Applications "$STAGING/Applications"

if [[ "$ADHOC" == true ]]; then
  cat > "$STAGING/请先阅读.txt" <<'README'
CellDock Modes — 安装说明

1. 把 CellDock Modes 拖到 Applications 文件夹。

2. 首次打开会被系统拦下。这个版本没有 Apple 开发者证书签名，
   所以 macOS 会说它"已损坏"——文件其实是完好的，这只是未签名
   软件从网络下载后的标准提示。

   绕过方法（任选其一）：

   a) 在"访达"里右键点击 CellDock Modes，选"打开"，
      再在弹窗里点"打开"。之后就能正常双击启动了。

   b) 在"终端"里执行：
      xattr -dr com.apple.quarantine "/Applications/CellDock Modes.app"

3. 首次启动会请求麦克风和通讯录权限。麦克风用于通话，
   通讯录用于在短信和来电中显示联系人姓名。都可以拒绝，
   只是相应功能不可用。

关于更新：此版本停用了自动更新。官方更新源提供的是不含本地
改动的版本，装上会覆盖它们。如需更新请从源码重新构建。
README
fi

/bin/rm -f -- "$DMG_PATH"
hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

print ""
print "=== Done ==="
print "$DMG_PATH"
ls -lh "$DMG_PATH" | awk '{ print "Size      : " $5 }'
if [[ "$ADHOC" == true ]]; then
  print "Signing   : ad-hoc — recipients must clear the quarantine flag,"
  print "            instructions are included in the image."
fi
