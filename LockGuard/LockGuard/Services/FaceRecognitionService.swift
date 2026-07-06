//
//  FaceRecognitionService.swift
//  LockGuard
//
//  Placeholder for the presence/face-recognition engine. Intentionally empty
//  of real logic for now — the onboarding flow only needs to know that camera
//  access exists. Capture and Vision work lands in a later milestone.
//

import Foundation

@MainActor
final class FaceRecognitionService {
    static let shared = FaceRecognitionService()
    private init() {}

    // Face recognition pipeline is not implemented yet.
}
