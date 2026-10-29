#!/usr/bin/env bash
# Builds precompiled XCFrameworks for Swift Package Manager (iOS + macOS).
# CocoaPods consumers still compile from source via cargokit (see ios/rhttp.podspec).
#
# The slices are dynamic `rhttp.framework` bundles, matching what the CocoaPods
# build produces: flutter_rust_bridge opens `rhttp.framework/rhttp` at runtime,
# and Dart resolves the FFI symbols with dlsym, so a static library would have
# them dead-stripped from the app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/rhttp"
RUST_DIR="$PKG/rust"
IOS_DIR="$PKG/ios"
MACOS_DIR="$PKG/macos"
LIB_NAME=rhttp
OUT="$ROOT/build/spm"
VERSION="$(sed -n 's/^version: *//p' "$PKG/pubspec.yaml" | head -1)"

export IPHONEOS_DEPLOYMENT_TARGET=11.0
export MACOSX_DEPLOYMENT_TARGET=10.12
# Same flags cargokit passes (see cargokit/build_tool/lib/src/builder.dart).
export RUSTFLAGS="--remap-path-prefix=$HOME/.cargo/=/.cargo/ --cfg reqwest_unstable"

if ! command -v rustup >/dev/null 2>&1; then
  echo "error: rustup is required. Install Rust from https://rustup.rs/" >&2
  exit 1
fi

build_dylib() {
  local target="$1"
  (cd "$RUST_DIR" && rustup target add "$target" >/dev/null && cargo build --release --lib --target "$target")
  local dylib="$RUST_DIR/target/$target/release/lib${LIB_NAME}.dylib"
  [[ -f "$dylib" ]] || { echo "error: expected $dylib" >&2; exit 1; }
}

dylib_for() {
  echo "$RUST_DIR/target/$1/release/lib${LIB_NAME}.dylib"
}

write_info_plist() {
  local path="$1" platform="$2" min_os="$3"
  local min_key=MinimumOSVersion
  [[ "$platform" == MacOSX ]] && min_key=LSMinimumSystemVersion
  cat > "$path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>${LIB_NAME}</string>
  <key>CFBundleIdentifier</key><string>dev.rhttp.${LIB_NAME}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>${LIB_NAME}</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleSupportedPlatforms</key><array><string>${platform}</string></array>
  <key>${min_key}</key><string>${min_os}</string>
</dict>
</plist>
EOF
}

# Flat bundle (iOS): rhttp.framework/{rhttp,Info.plist}
make_ios_framework() {
  local dir="$1" platform="$2"; shift 2
  local fw="$dir/${LIB_NAME}.framework"
  rm -rf "$fw" && mkdir -p "$fw"
  lipo -create "$@" -output "$fw/${LIB_NAME}"
  install_name_tool -id "@rpath/${LIB_NAME}.framework/${LIB_NAME}" "$fw/${LIB_NAME}"
  write_info_plist "$fw/Info.plist" "$platform" "$IPHONEOS_DEPLOYMENT_TARGET"
}

# Versioned bundle (macOS): rhttp.framework/Versions/A/{rhttp,Resources/Info.plist}
make_macos_framework() {
  local dir="$1"; shift
  local fw="$dir/${LIB_NAME}.framework"
  rm -rf "$fw" && mkdir -p "$fw/Versions/A/Resources"
  lipo -create "$@" -output "$fw/Versions/A/${LIB_NAME}"
  install_name_tool -id "@rpath/${LIB_NAME}.framework/Versions/A/${LIB_NAME}" "$fw/Versions/A/${LIB_NAME}"
  write_info_plist "$fw/Versions/A/Resources/Info.plist" MacOSX "$MACOSX_DEPLOYMENT_TARGET"
  ln -s A "$fw/Versions/Current"
  ln -s "Versions/Current/${LIB_NAME}" "$fw/${LIB_NAME}"
  ln -s Versions/Current/Resources "$fw/Resources"
}

echo "==> Building Rust dylibs..."
for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios aarch64-apple-darwin x86_64-apple-darwin; do
  build_dylib "$target"
done

rm -rf "$OUT"
make_ios_framework "$OUT/ios-device" iPhoneOS "$(dylib_for aarch64-apple-ios)"
make_ios_framework "$OUT/ios-sim" iPhoneSimulator "$(dylib_for aarch64-apple-ios-sim)" "$(dylib_for x86_64-apple-ios)"
make_macos_framework "$OUT/macos" "$(dylib_for aarch64-apple-darwin)" "$(dylib_for x86_64-apple-darwin)"

IOS_XCFW="$IOS_DIR/rhttp/rhttp.xcframework"
MACOS_XCFW="$MACOS_DIR/rhttp/rhttp.xcframework"
rm -rf "$IOS_XCFW" "$MACOS_XCFW"

echo "==> Creating $IOS_XCFW"
xcodebuild -create-xcframework \
  -framework "$OUT/ios-device/${LIB_NAME}.framework" \
  -framework "$OUT/ios-sim/${LIB_NAME}.framework" \
  -output "$IOS_XCFW"

echo "==> Creating $MACOS_XCFW"
xcodebuild -create-xcframework \
  -framework "$OUT/macos/${LIB_NAME}.framework" \
  -output "$MACOS_XCFW"

echo "Done. Commit ios/rhttp/rhttp.xcframework and macos/rhttp/rhttp.xcframework when releasing."
