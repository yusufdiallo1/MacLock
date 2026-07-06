//
//  PermissionsManager.swift
//  LockGuard
//
//  Single source of truth for permission state. Queries the system, drives
//  the request prompts, and publishes changes so the UI can react.
//

import AppKit
import AVFoundation
import ApplicationServices
import Combine

@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published private(set) var accessibility: PermissionStatus = .notDetermined
    @Published private(set) var camera: PermissionStatus = .notDetermined

    private init() {
        refreshAll()
    }

    /// True when every permission LockGuard needs has been granted.
    var allGranted: Bool {
        accessibility.isGranted && camera.isGranted
    }

    func status(for permission: Permission) -> PermissionStatus {
        switch permission {
        case .accessibility: return accessibility
        case .camera:        return camera
        }
    }

    // MARK: - Refresh

    func refreshAll() {
        accessibility = Self.currentAccessibilityStatus()
        camera = Self.currentCameraStatus()
    }

    // MARK: - Requests

    /// Requests a permission and refreshes state. Accessibility cannot show a
    /// modal prompt, so we open its System Settings pane instead.
    func request(_ permission: Permission) async {
        switch permission {
        case .accessibility: await requestAccessibility()
        case .camera:        await requestCamera()
        }
    }

    private func requestAccessibility() async {
        // Passing the prompt option surfaces the system's "grant access" dialog
        // if access hasn't been determined yet.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // In case the prompt is dismissed, take the user straight to the pane.
        openSystemSettings(pane: "Privacy_Accessibility")
        accessibility = Self.currentAccessibilityStatus()
    }

    private func requestCamera() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            camera = .granted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            camera = granted ? .granted : .denied
        case .denied, .restricted:
            camera = .denied
            openSystemSettings(pane: "Privacy_Camera")
        @unknown default:
            camera = .denied
        }
    }

    // MARK: - System status queries

    private static func currentAccessibilityStatus() -> PermissionStatus {
        AXIsProcessTrusted() ? .granted : .notDetermined
    }

    private static func currentCameraStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:            return .granted
        case .denied, .restricted:   return .denied
        case .notDetermined:         return .notDetermined
        @unknown default:            return .denied
        }
    }

    // MARK: - Helpers

    func openSystemSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
