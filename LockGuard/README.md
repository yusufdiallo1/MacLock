# LockGuard

A macOS menu-bar app that gates individual applications and folders behind
face recognition and a master password. Lock Chrome, Messages, a Documents
folder — when they're opened, LockGuard covers them with a frosted "Liquid
Glass" auth overlay until you authenticate with your face (or password).

> **Security note.** LockGuard's Face Unlock uses the built-in camera and
> Apple's **Vision** framework for *convenience-level* recognition. It is **not**
> equivalent to Apple's Face ID and can be fooled by a photo. For anything
> sensitive, rely on the master password. Folder locking uses a placeholder XOR
> scramble (clearly marked in code) — it deters casual snooping, not a
> determined attacker.

---

## Features

- **Per-app locking** — lock any installed app; opening it triggers an auth
  overlay positioned over that app's window (full-screen fallback if the window
  can't be targeted).
- **Per-folder locking** — a locked folder's contents are stashed to a hidden
  container until you authenticate.
- **Face Unlock** — multi-angle enrollment (9 captures), live camera preview,
  and an adaptive profile that keeps learning your face from successful unlocks.
- **Master password** — SHA-256 + salt, stored in the Keychain; the fallback
  whenever face isn't available.
- **Session of access** — after you unlock an app, it stays unlocked until the
  Mac sleeps, a session timeout elapses, or you lock everything manually.
- **Hardening** — rate limiting (5 fails → password-only + 30 s cooldown),
  3-minute inactivity wipe of the in-memory face profile, an encrypted auth log,
  a self-lock guard (LockGuard can't lock itself), Accessibility-revocation
  detection, and a KeepAlive LaunchAgent that relaunches LockGuard if it's
  killed.
- **Emergency kill switch** — `⌃⌥⇧⌫` instantly locks everything and disables
  face unlock for 60 seconds.
- **Settings** — a native Settings window (Locked Apps / Authentication /
  Behavior / About) that itself requires authentication to open.

---

## Permissions required

LockGuard is **not sandboxed** — the sandbox blocks the cross-app
`NSWorkspace` activation notifications LockGuard needs to know when a locked app
is opened. It is distributed with a Developer ID signature (or, for local
builds, a self-signed certificate) rather than through the Mac App Store.

| Permission | Why | Where it's requested |
|---|---|---|
| **Accessibility** | Read the target app's focused-window frame (via the AX API) so the overlay covers exactly that window; detect revocation to re-lock. | First-launch onboarding → System Settings ▸ Privacy & Security ▸ Accessibility |
| **Camera** | Face enrollment and Face Unlock (`AVFoundation` + Vision). `NSCameraUsageDescription` is set in `Info.plist`. | First-launch onboarding / first face use |
| **Keychain** | Store the salted password hash, the face profile, and the AES-GCM key for the encrypted auth log. Uses the data-protection keychain for silent, app-scoped access. | Automatic (no prompt once signed with a stable identity) |

If Accessibility is revoked while LockGuard is running, it locks everything
immediately and reopens the Accessibility pane.

---

## Building

Requirements: **macOS 26+**, **Xcode 26+**. Menu-bar-only app (`LSUIElement`),
`.accessory` activation policy — no dock icon.

```sh
open LockGuard.xcodeproj      # then ⌘R in Xcode
# or from the command line:
xcodebuild -project LockGuard.xcodeproj -scheme LockGuard -configuration Debug \
  -destination 'platform=macOS,arch=arm64' build
```

### Code signing (important)

macOS ties **TCC permission grants** (Accessibility, Camera, Keychain) to the
app's **code-signing identity**. If the app is ad-hoc signed, every rebuild
looks like a *different* app and macOS re-prompts for permissions (and window-
frame reads fail → the overlay blurs the whole screen). To make permissions
**persist across rebuilds**, LockGuard is signed with a stable identity.

The project uses **manual signing** with an identity named `LockGuard Dev` and
`ENABLE_DEBUG_DYLIB = NO` (a single self-contained binary — required so manual
signing doesn't split into mismatched Team IDs). Create the local self-signed
certificate once:

```sh
# 1. Generate a self-signed code-signing cert
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
  -subj "/CN=LockGuard Dev" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"
openssl pkcs12 -export -inkey key.pem -in cert.pem -out cert.p12 -passout pass:lockguard \
  -name "LockGuard Dev" -legacy -macalg sha1

# 2. Import into the login keychain
security import cert.p12 -k ~/Library/Keychains/login.keychain-db -P lockguard -T /usr/bin/codesign

# 3. Let codesign use the key without prompting
security unlock-keychain -p "" ~/Library/Keychains/login.keychain-db
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "LockGuard Dev" \
  -k "" ~/Library/Keychains/login.keychain-db
```

Then build normally. Grant Accessibility and Camera **once**; they persist
across subsequent rebuilds.

> Using your own Apple Developer ID team instead? Set `CODE_SIGN_STYLE = Automatic`
> and select your team in *Signing & Capabilities* — that's a stable identity too.

---

## Architecture

Services (all `@MainActor` singletons, held by `AppDelegate`):

| Service | Role |
|---|---|
| `AppLockService` | Locked apps (by bundle ID); watches activation, posts the auth-overlay request, tracks per-app session grants. |
| `LockManager` | Folders + a mirror of the app list for the popover. |
| `FolderLockService` | Watches locked folders (`DispatchSource`), stashes/restores contents. |
| `WindowOverlayService` | Positions the borderless auth overlay over the target window (AX frame + `AXObserver` tracking); full-screen fallback. |
| `FaceAuthService` | Vision landmark → geometric profile matching; enrollment; Keychain storage. |
| `PasswordAuthService` | Salted SHA-256 password; emergency kill switch. |
| `AuthCoordinator` | Single auth brain: `requireAuth` modal, rate limiting, inactivity wipe, records every outcome. |
| `AuthLogService` / `CryptoBox` | AES-GCM encrypted auth log; shared crypto key. |
| `FaceProfileStore` | Adaptive-training sample store (encrypted, anchor-protected). |
| `EnforcementService` | Accessibility-revocation watcher, lock-on-sleep, session timeout. |
| `LaunchAgentService` | KeepAlive LaunchAgent (deletion protection) + launch-at-login. |
| `BehaviorSettings` | Persisted Behavior-tab preferences. |

**Auth flow:** locked app activates → `AppLockService` posts a request →
`WindowOverlayService` shows `AuthOverlayView` over the window → Face Unlock is
tried first, password is the fallback → on success the app gets a session of
access; on cancel the app is hidden and stays locked.
