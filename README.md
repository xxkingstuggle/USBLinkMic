# USB LinkMic

USB LinkMic is a macOS + Android tool for USB-based phone microphone input and wired phone network workflows.

## What It Does

- Android microphone to Mac, primarily through USB + ADB reverse.
- Android phone network to Mac through USB CDC-NCM control from the Mac app.
- Mac network to Android through the gnirehtet-style VPN relay path.
- Mac UI is a native SwiftUI app.
- Android UI is a native Jetpack Compose app.

The app does not read, write, or configure Clash/VPN proxy software on macOS.

## Repository Layout

- `mac-native/` - native macOS SwiftUI app.
- `android/` - Android companion app.
- `Assets/` - screenshots and visual assets.

Generated files such as `.app`, `.apk`, Gradle caches, Xcode build products, and signing keys are intentionally excluded from Git.

## Build

### macOS

```sh
xcodebuild \
  -project mac-native/USBLinkMicNative.xcodeproj \
  -scheme USBLinkMicNative \
  -configuration Debug \
  -derivedDataPath mac-native/build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### Android

```sh
cd android
ANDROID_HOME="$HOME/Library/Android/sdk" \
JAVA_HOME=/opt/homebrew/Cellar/openjdk@21/21.0.11/libexec/openjdk.jdk/Contents/Home \
./gradlew :app:assembleDebug
```

For release signing, provide a local `android/app/key.jks` and the `KEY_ALIAS`, `KEY_PASSWORD`, and `STORE_PASSWORD` environment variables. Do not commit signing keys.

## Runtime Notes

- ADB mode requires USB debugging authorization.
- Android microphone mode requires microphone permission.
- Mac audio output should generally be set to BlackHole when the phone microphone needs to appear as a virtual microphone to meeting apps.
- USB CDC-NCM switching requires the Android phone to be unlocked.

## License Notice

This project includes code derived from AndroidMic and gnirehtet-style networking components. Preserve upstream license notices when redistributing.
