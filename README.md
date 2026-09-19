# ViKey

ViKey is a macOS menu-bar Vietnamese Telex input app. It requires macOS 13 or later and Accessibility permission.

## Development

```sh
swift test
swift run ViKey
```

The app appears as `VI` or `EN` in the menu bar. Grant Accessibility permission in System Settings when macOS requests it.

## Build an app bundle

```sh
bash Scripts/build-app.sh
open dist/ViKey.app
```

The script produces `dist/ViKey.app`, validates its code signature, and uses ad-hoc signing by default.

For a distributable signed release, provide a Developer ID Application certificate and release version metadata:

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
VERSION=1.0.0 BUILD_NUMBER=1 \
bash Scripts/build-app.sh
```

Notarization requires Apple credentials and is the final release step before distributing the signed bundle outside your own machine.