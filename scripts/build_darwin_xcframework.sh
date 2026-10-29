#!/usr/bin/env bash
# Builds precompiled XCFrameworks for Swift Package Manager (iOS + macOS).
# CocoaPods consumers still compile from source via cargokit (see ios/rhttp.podspec).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/rhttp"
CARGOKIT="$PKG/cargokit"
IOS_DIR="$PKG/ios"
MACOS_DIR="$PKG/macos"
RUST_REL="../rust"
LIB_NAME=rhttp
IOS_HEADERS="$PKG/ios/rhttp/include"
MACOS_HEADERS="$PKG/macos/rhttp/include"

if ! command -v rustup >/dev/null 2>&1; then
  echo "error: rustup is required. Install Rust from https://rustup.rs/" >&2
  exit 1
fi

build_static_lib() {
  local platform_name="$1"
  local archs="$2"
  local out_root="$3"

  mkdir -p "$out_root/temp" "$out_root/products/rhttp"

  export PLATFORM_NAME="$platform_name"
  export ARCHS="$archs"
  export CONFIGURATION=Release
  export TARGET_TEMP_DIR="$out_root/temp"
  export BUILT_PRODUCTS_DIR="$out_root/products"
  export PODS_CONFIGURATION_BUILD_DIR="$out_root/products"
  export PODS_TARGET_SRCROOT="$4"
  export PRODUCT_NAME=rhttp
  export PODS_ROOT="$4/.."
  export SRCROOT="$4/.."
  export EXECUTABLE_PATH=rhttp

  # cargokit/build_pod.sh sources flutter_export_environment.sh when present.
  sh "$CARGOKIT/build_pod.sh" "$RUST_REL" "$LIB_NAME"

  local lib="$out_root/products/rhttp/lib${LIB_NAME}.a"
  if [[ ! -f "$lib" ]]; then
    echo "error: expected static library at $lib" >&2
    exit 1
  fi
}

IOS_DEVICE_LIB="$ROOT/build/spm/ios-device/products/rhttp/lib${LIB_NAME}.a"
IOS_SIM_LIB="$ROOT/build/spm/ios-sim/products/rhttp/lib${LIB_NAME}.a"
MACOS_LIB="$ROOT/build/spm/macos/products/rhttp/lib${LIB_NAME}.a"

echo "==> Building iOS device (arm64)..."
build_static_lib iphoneos arm64 "$ROOT/build/spm/ios-device" "$IOS_DIR"

echo "==> Building iOS simulator (arm64 + x86_64)..."
build_static_lib iphonesimulator "arm64 x86_64" "$ROOT/build/spm/ios-sim" "$IOS_DIR"

echo "==> Building macOS (arm64 + x86_64)..."
build_static_lib macosx "arm64 x86_64" "$ROOT/build/spm/macos" "$MACOS_DIR"

IOS_XCFW="$IOS_DIR/rhttp/rhttp.xcframework"
MACOS_XCFW="$MACOS_DIR/rhttp/rhttp.xcframework"
rm -rf "$IOS_XCFW" "$MACOS_XCFW"

echo "==> Creating $IOS_XCFW"
xcodebuild -create-xcframework \
  -library "$IOS_DEVICE_LIB" -headers "$IOS_HEADERS" \
  -library "$IOS_SIM_LIB" -headers "$IOS_HEADERS" \
  -output "$IOS_XCFW"

echo "==> Creating $MACOS_XCFW"
xcodebuild -create-xcframework \
  -library "$MACOS_LIB" -headers "$MACOS_HEADERS" \
  -output "$MACOS_XCFW"

echo "Done. Commit ios/rhttp/rhttp.xcframework and macos/rhttp/rhttp.xcframework when releasing."
