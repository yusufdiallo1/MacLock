//
//  KeyableWindow.swift
//  LockGuard
//
//  A borderless NSWindow that CAN become key/main. Plain borderless windows
//  return `canBecomeKey = false`, so text fields can't be typed into and
//  buttons don't get keyboard focus — that broke the auth overlay's password
//  field and the Settings auth gate. This subclass fixes it.
//

import AppKit

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// A keyable borderless window that also reports when it closes, so the
/// AuthCoordinator can always resolve its pending continuation.
final class GateKeyableWindow: KeyableWindow {
    var onClose: (() -> Void)?
    override func close() { onClose?(); onClose = nil; super.close() }
}
