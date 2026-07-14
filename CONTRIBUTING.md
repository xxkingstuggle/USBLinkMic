# Contributing to USB LinkMic

Thanks for helping improve USB LinkMic. Small, focused changes with clear reproduction and testing notes are the easiest to review.

## Before you start

- Search existing issues before opening a new one.
- Use the repository issue forms; USB networking reports need device and ROM details to be actionable.
- Open an issue before a large refactor, protocol change, new dependency, or UI redesign.
- Never include signing keys, provisioning profiles, device identifiers, private logs, or other secrets.

## Development setup

### Android

Requirements: JDK 21 and an Android SDK with API 36 available.

```sh
cd android
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
```

### macOS

Requirements: Xcode 26. Rebuilding the bundled reverse-tethering relay also requires Rust.

```sh
./scripts/build-gnirehtet-relay.sh

xcodebuild \
  -project mac-native/USBLinkMicNative.xcodeproj \
  -scheme USBLinkMicNative \
  -configuration Debug \
  -derivedDataPath mac-native/build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Pull requests

1. Keep each pull request focused on one problem.
2. Explain the user-visible behavior and why the change is needed.
3. Add or update tests when behavior changes.
4. Test the affected connection path on real devices when possible.
5. Include before/after screenshots for UI changes and sanitized logs for connection fixes.
6. Update both `README.md` and `README.zh-CN.md` when user-facing documentation changes.

The most useful test report identifies the Mac model/architecture, macOS version, Android device, Android version, ROM/vendor, USB function, connection mode, and exact commands run.

## Project boundaries

- `android/` contains the Kotlin/Compose app and Android VPN/streaming services.
- `mac-native/` contains the SwiftUI app, Core Audio path, ADB orchestration, and relay launcher.
- `third_party/gnirehtet/` is pinned upstream source. Keep upstream attribution and license files intact.
- `mac-native/USBLinkMicNative/Resources/gnirehtet-relay` must be reproducible from the pinned source and build script.

By submitting a contribution, you agree that it may be distributed under the repository's [MIT License](LICENSE). Third-party code remains under its original license.
