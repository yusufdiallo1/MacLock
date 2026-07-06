# LockGuard

A menu-bar-only macOS app (macOS 14+) that guards your Mac by *presence* — it
locks when you step away and recognizes your face to unlock when you return.

This milestone sets up the project skeleton and the first-launch permission
flow only. There is no product UI beyond onboarding yet.

## Requirements

- macOS 14.0+
- Xcode 15+

## Open & run

Open `LockGuard.xcodeproj` in Xcode and run the **LockGuard** scheme.

If you have [XcodeGen](https://github.com/yonyz/XcodeGen) installed, you can
regenerate the project from `project.yml`:

```sh
brew install xcodegen
xcodegen generate
```

## What's here

| Area | Purpose |
|------|---------|
| **Menu bar only** | `LSUIElement = YES` in `Info.plist`; `NSApp.setActivationPolicy(.accessory)`. No dock icon, no app-switcher entry. |
| **Status item** | `StatusItemController` owns an `NSStatusItem` with a custom SF Symbol lock icon that flips between `lock.open` and `lock.shield.fill` as the app arms. |
| **App entry** | `LockGuardApp` (`@main`) uses `@NSApplicationDelegateAdaptor` to hand lifecycle to `AppDelegate`. |
| **Permissions** | `PermissionsManager` queries and requests **Accessibility** and **Camera** access and publishes state. |
| **Onboarding** | A clean sheet presented on first launch — a "sentry rail" that lights amber as each permission is granted. |

## Folder structure

```
LockGuard/
├── LockGuardApp.swift          # @main entry point
├── AppDelegate.swift           # lifecycle, status item, onboarding coordination
├── Models/
│   └── Permission.swift        # Permission + PermissionStatus value types
├── Views/
│   ├── OnboardingView.swift    # first-launch permission flow
│   ├── PermissionRow.swift     # one node on the sentry rail
│   └── OnboardingWindowController.swift
├── Services/
│   ├── PermissionsManager.swift    # query + request permissions
│   ├── StatusItemController.swift  # menu bar item + menu
│   └── FaceRecognitionService.swift # placeholder for a later milestone
├── Utilities/
│   ├── LaunchState.swift       # first-launch persistence
│   └── Theme.swift             # onboarding visual language
└── Resources/
    ├── Info.plist              # LSUIElement, camera usage string
    ├── LockGuard.entitlements  # sandbox + camera
    └── Assets.xcassets
```

## Permissions

- **Camera** — prompted with a standard system dialog (`AVCaptureDevice`), backed
  by `NSCameraUsageDescription` in `Info.plist`.
- **Accessibility** — cannot show a modal prompt; the app calls
  `AXIsProcessTrustedWithOptions` and opens the System Settings pane. State
  refreshes automatically when you return to the app.
