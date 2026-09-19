# ViKey

ViKey is a macOS menu-bar Vietnamese Telex input app. It requires macOS 13 or later and Accessibility permission.

## Development

```sh
swift test
swift run ViKey
```

The app appears as `VI` or `EN` in the menu bar. Grant Accessibility permission in System Settings when macOS requests it.

## Bảng gõ Telex

| Phím | Kết quả | Ví dụ |
| --- | --- | --- |
| `s`, `f`, `r`, `x`, `j` | sắc, huyền, hỏi, ngã, nặng | `tieengs` -> tiếng |
| `aa`, `ee`, `oo` | â, ê, ô | `ddaays` -> đấy |
| `aw`, `ow`, `uw` | ă, ơ, ư | `nguowif` -> người |
| `dd` hoặc `did` | đ | `did` -> đi |
| `uow`, `chuaw` | ươ, ưa | `chuaw` -> chưa |
| `z` | bỏ dấu thanh | `asz` -> a |

## Build an app bundle

```sh
bash Scripts/build-app.sh
open dist/ViKey.app
```

The script produces `dist/ViKey.app`, validates its code signature, and uses ad-hoc signing by default.

Notarization requires Apple credentials and is the final release step before distributing the signed bundle outside your own machine.
