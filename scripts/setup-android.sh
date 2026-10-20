#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

: "${ANDROID_HOME:?Set ANDROID_HOME to your Android SDK directory}"
# Accept the SDK licenses explicitly with `sdkmanager --licenses` first.
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" "ndk;27.3.13750724"
rustup target add aarch64-linux-android

mkdir -p .once
if [ ! -f .once/debug.keystore ]; then
  keytool -genkeypair -noprompt \
    -keystore .once/debug.keystore -storepass android -keypass android \
    -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US"
fi

printf '\nSet ANDROID_NDK_HOME=%s/ndk/27.3.13750724 before building.\n' "$ANDROID_HOME"
