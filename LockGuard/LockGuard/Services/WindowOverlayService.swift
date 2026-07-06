//
//  WindowOverlayService.swift
//  LockGuard
//
//  Presents the auth overlay directly over a locked app's focused window.
//
//  It reads the target window's frame through the Accessibility API
//  (AXUIElementCreateApplication → focused window → position/size), places a
//  borderless, floating NSWindow exactly over it, frosts the app behind a
//  .ultraThinMaterial visual-effect view, and centers the auth card on top.
//  An AXObserver keeps the overlay glued to the window as it moves or resizes.
//
//  If the frame can't be read — the app blocks Accessibility, isn't trusted
//  yet, or exposes no window — it falls back to a full-screen overlay so the
//  gate still holds.
//
//  Coordinate note: the Accessibility API reports frames in *screen* space with
//  a top-left origin and y growing downward. AppKit windows use a bottom-left
//  origin with y growing upward. `Self.cocoaFrame(fromAX:)` bridges the two.
//

import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class WindowOverlayService {
    static let shared = WindowOverlayService()

    /// Called when the user authenticates (or the overlay is cancelled). The
    /// caller uses this to release the challenge guard (AppLockService.clearPending).
    var onResolved: (() -> Void)?

    private var overlayWindow: NSWindow?
    private var axObserver: AXObserver?
    private var observedElement: AXUIElement?
    private var targetPID: pid_t?

    // MARK: - Presentation

    /// Present the overlay over `app`'s focused window. `pid` is the running
    /// app's process id; `appName` labels the card. `forceFullScreen` covers the
    /// whole screen (used for folder locks, which have no window to target).
    func present(forPID pid: pid_t, appName: String, forceFullScreen: Bool = false) {
        // If an overlay is already up, tear it down first — one at a time.
        dismiss(callResolved: false)
        targetPID = pid

        let frame = forceFullScreen ? nil : Self.focusedWindowFrame(forPID: pid)
        let overlayFrame = frame ?? Self.fullScreenFrame()
        let isPreciseFit = frame != nil

        let icon = NSRunningApplication(processIdentifier: pid)?.icon

        let window = makeOverlayWindow(
            frame: overlayFrame,
            appName: appName,
            appIcon: icon,
            targetPID: pid,
            isFullScreenFallback: !isPreciseFit
        )
        overlayWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Only track window movement when we actually fit a specific window.
        if isPreciseFit {
            startTrackingWindow(pid: pid)
        }
    }

    /// Public dismissal for the auth layer (or a successful placeholder unlock).
    func dismiss() {
        dismiss(callResolved: true)
    }

    private func dismiss(callResolved: Bool) {
        stopTrackingWindow()
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        targetPID = nil
        if callResolved { onResolved?() }
    }

    // MARK: - Window construction

    private func makeOverlayWindow(
        frame: NSRect,
        appName: String,
        appIcon: NSImage?,
        targetPID: pid_t,
        isFullScreenFallback: Bool
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        // A precise per-window overlay floats just above normal windows; the
        // full-screen fallback shields at a higher level so nothing peeks past.
        window.level = isFullScreenFallback ? .screenSaver : .floating
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        // Show over full-screen spaces and follow the user across spaces.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Backdrop. Per-window fit: frost the app window (Liquid Glass blur).
        // Full-screen fallback (AX couldn't target a window): DON'T frost the
        // whole screen — that's jarring. Use a light dim so the desktop shows
        // through, with just the compact card centered on top.
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        blur.autoresizingMask = [.width, .height]
        blur.wantsLayer = true
        if isFullScreenFallback {
            // Light dim, not a full frost.
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .inactive          // minimal blur
            blur.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        } else {
            blur.material = .hudWindow      // frosts the app window behind it
            blur.blendingMode = .behindWindow
            blur.state = .active
        }

        // The full auth card, centered on the blur.
        let card = AuthOverlayView(
            appName: appName,
            appIcon: appIcon,
            verifyPassword: { PasswordAuthService.shared.verify($0) },
            onSuccess: { [weak self] in self?.dismiss() },
            onCancel: { [weak self] in self?.dismiss() },
            onQuitApp: { [weak self] in
                NSRunningApplication(processIdentifier: targetPID)?.terminate()
                self?.dismiss()
            }
        )
        let hosting = NSHostingView(rootView: card)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        blur.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
            hosting.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
        ])

        window.contentView = blur
        return window
    }

    // MARK: - Accessibility frame reading

    /// The screen-space Cocoa frame of `pid`'s focused window, or `nil` if it
    /// can't be read (AX blocked, no window, unexpected shape) or the window
    /// isn't actually on screen (e.g. minimized → off-screen AX coordinates).
    private static func focusedWindowFrame(forPID pid: pid_t) -> NSRect? {
        let appElement = AXUIElementCreateApplication(pid)

        let raw: NSRect?
        if let window = copyAXValue(appElement, kAXFocusedWindowAttribute),
           CFGetTypeID(window) == AXUIElementGetTypeID() {
            raw = frame(of: window as! AXUIElement)
        } else {
            // Some apps expose windows but no "focused" one; try the first window.
            raw = firstWindowFrame(of: appElement)
        }

        guard let candidate = raw else { return nil }
        // A minimized / off-Space window reports valid-looking but off-screen
        // coordinates. If the frame doesn't meaningfully intersect any screen,
        // treat it as unreadable so the caller uses the full-screen fallback.
        guard Self.intersectsAnyScreen(candidate) else { return nil }
        return candidate
    }

    /// True if `frame` overlaps the union of all screens by a non-trivial area.
    private static func intersectsAnyScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            let hit = screen.frame.intersection(frame)
            return hit.width > 4 && hit.height > 4
        }
    }

    private static func firstWindowFrame(of appElement: AXUIElement) -> NSRect? {
        guard let windowsValue = copyAXValue(appElement, kAXWindowsAttribute),
              let windows = windowsValue as? [AXUIElement],
              let first = windows.first
        else { return nil }
        return frame(of: first)
    }

    /// Read a window element's position + size and convert to a Cocoa frame.
    private static func frame(of window: AXUIElement) -> NSRect? {
        guard
            let posValue = copyAXValue(window, kAXPositionAttribute),
            let sizeValue = copyAXValue(window, kAXSizeAttribute)
        else { return nil }

        var axPoint = CGPoint.zero
        var axSize = CGSize.zero
        // AXValue is a CF type; check dynamically rather than force-casting so a
        // misbehaving app returning an odd type on `.success` degrades to the
        // fallback instead of crashing. (CFGetTypeID guards the AXValueGetValue
        // calls, which themselves return false for the wrong AXValueType.)
        guard
            CFGetTypeID(posValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        let posAX = posValue as! AXValue
        let sizeAX = sizeValue as! AXValue
        guard
            AXValueGetValue(posAX, .cgPoint, &axPoint),
            AXValueGetValue(sizeAX, .cgSize, &axSize),
            axSize.width > 1, axSize.height > 1
        else { return nil }

        return cocoaFrame(fromAX: CGRect(origin: axPoint, size: axSize))
    }

    /// Copy an AX attribute, returning `nil` on any error (including the
    /// `.apiDisabled` / `.notAuthorized` results apps get when they block AX).
    private static func copyAXValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }

    // MARK: - Coordinate conversion

    /// AX frames are top-left origin, y-down, in *global* screen space where the
    /// zero-origin (primary/menu-bar) display's top-left is (0,0). Cocoa is
    /// bottom-left origin, y-up. A single global flip about the zero-origin
    /// screen's height is correct for windows on any display (secondary displays
    /// above primary have negative AX y; below have large positive y).
    private static func cocoaFrame(fromAX axFrame: CGRect) -> NSRect {
        // The zero-origin screen — explicitly, not just screens.first — is the
        // one AppKit and AX both anchor global coordinates to.
        let zeroScreen = NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.screens.first
        guard let flipHeight = zeroScreen?.frame.height else { return axFrame }
        let flippedY = flipHeight - axFrame.origin.y - axFrame.height
        return NSRect(
            x: axFrame.origin.x,
            y: flippedY,
            width: axFrame.width,
            height: axFrame.height
        )
    }

    /// Union of every screen — the full-screen fallback covers all displays, not
    /// just the one the locked app happens to sit on.
    private static func fullScreenFrame() -> NSRect {
        let screens = NSScreen.screens
        guard let first = screens.first else {
            return NSRect(x: 0, y: 0, width: 1440, height: 900)
        }
        return screens.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    // MARK: - Window-move / resize tracking via AXObserver

    /// Observe the target app for window move/resize and keep the overlay
    /// pinned. If the observer can't be created (AX blocked), the overlay
    /// simply stays where it was first placed — still a valid gate.
    private func startTrackingWindow(pid: pid_t) {
        var observer: AXObserver?
        // The callback fires on the run loop the source is added to — the main
        // loop (present()/stopTrackingWindow() are @MainActor, and we add the
        // source to the main loop below). So it's already main-actor-isolated;
        // assume-isolated and act synchronously rather than deferring through a
        // Task, which would open an async gap over the unretained `self` pointer.
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let service = Unmanaged<WindowOverlayService>
                .fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            MainActor.assumeIsolated {
                if name == (kAXUIElementDestroyedNotification as String) {
                    // The window we were pinned to went away — drop the overlay
                    // (and release the challenge guard via onResolved).
                    service.dismiss()
                } else {
                    service.repositionToTarget()
                }
            }
        }

        guard AXObserverCreate(pid, callback, &observer) == .success,
              let observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Register on the app element; notifications bubble up from its windows.
        AXObserverAddNotification(observer, appElement, kAXWindowMovedNotification as CFString, refcon)
        AXObserverAddNotification(observer, appElement, kAXWindowResizedNotification as CFString, refcon)
        AXObserverAddNotification(observer, appElement, kAXUIElementDestroyedNotification as CFString, refcon)

        // Use the main run loop explicitly so add/remove always target the same
        // loop regardless of executor details.
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        axObserver = observer
        observedElement = appElement
    }

    private func stopTrackingWindow() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
            if let element = observedElement {
                AXObserverRemoveNotification(observer, element, kAXWindowMovedNotification as CFString)
                AXObserverRemoveNotification(observer, element, kAXWindowResizedNotification as CFString)
                AXObserverRemoveNotification(observer, element, kAXUIElementDestroyedNotification as CFString)
            }
        }
        axObserver = nil
        observedElement = nil
    }

    /// Re-read the target window's frame and move/resize the overlay to match.
    /// If the frame can no longer be read, leave the overlay in place.
    private func repositionToTarget() {
        guard let window = overlayWindow, let pid = targetPID else { return }
        guard let frame = Self.focusedWindowFrame(forPID: pid) else { return }
        window.setFrame(frame, display: true, animate: false)
    }
}
