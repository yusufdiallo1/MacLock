//
//  FaceProfileStore.swift
//  LockGuard
//
//  Adaptive face "training": persists every enrollment capture and every
//  accepted-auth face vector (encrypted with the shared CryptoBox AES-GCM key),
//  and periodically rebuilds the stored profile so LockGuard keeps learning
//  your face over time.
//
//  This is honest running-statistics (recomputing the mean/std over accumulated
//  samples), NOT machine learning. Safeguards: a ring-buffer cap and a strict
//  z-score gate on accepted samples so an impostor who slips through once can't
//  drift the profile.
//

import Foundation

@MainActor
final class FaceProfileStore {
    static let shared = FaceProfileStore()

    /// Cap on how many samples we keep — bounds file size and limits how far a
    /// bad sample could ever move the profile.
    private static let maxSamples = 120
    /// Refine the stored profile after this many new accepted samples.
    private static let refineEvery = 8
    /// Accepted-auth samples must be within this RMS-z of the current profile to
    /// be admitted for training (tighter than the unlock threshold).
    private static let trainingAdmitZ: Float = 1.2

    private let fileURL: URL
    private var samples: [[Float]] = []
    private var acceptedSinceRefine = 0

    private init() {
        fileURL = CryptoBox.appSupportDirectory().appendingPathComponent("face.samples.enc")
        samples = load()
    }

    // MARK: - Ingest

    /// Store the enrollment captures (called at the end of enroll()).
    func appendEnrollmentSamples(_ vectors: [[Float]]) {
        samples.append(contentsOf: vectors)
        trim()
        persist()
    }

    /// Store an accepted-auth vector for adaptive refinement, if it's close
    /// enough to the current profile. Returns a rebuilt profile every
    /// `refineEvery` samples so the caller can re-store it.
    func appendAcceptedSample(
        _ vector: [Float],
        currentProfile: FaceAuthService.FaceProfile
    ) -> FaceAuthService.FaceProfile? {
        // Gate: only admit samples that clearly match, so training can't drift.
        guard vector.count == currentProfile.mean.count,
              Self.rmsZ(vector, currentProfile) <= Self.trainingAdmitZ else { return nil }

        samples.append(vector)
        trim()
        persist()

        acceptedSinceRefine += 1
        guard acceptedSinceRefine >= Self.refineEvery else { return nil }
        acceptedSinceRefine = 0
        return FaceAuthService.profile(from: samples)
    }

    /// All stored samples (for a full rebuild, e.g. on demand).
    func rebuildProfile() -> FaceAuthService.FaceProfile? {
        FaceAuthService.profile(from: samples)
    }

    func clear() {
        samples.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Helpers

    private func trim() {
        if samples.count > Self.maxSamples {
            samples.removeFirst(samples.count - Self.maxSamples)
        }
    }

    private static func rmsZ(_ v: [Float], _ p: FaceAuthService.FaceProfile) -> Float {
        var sumSq: Float = 0
        let n = min(v.count, p.mean.count)
        var i = 0
        while i < n {
            let diff: Float = v[i] - p.mean[i]
            let z: Float = diff / p.std[i]
            sumSq += z * z
            i += 1
        }
        let mean: Float = sumSq / Float(max(n, 1))
        return mean.squareRoot()
    }

    // MARK: - Persistence (encrypted)

    private func persist() {
        // Encode as [count][len][floats…] per sample via JSON for simplicity.
        guard let plaintext = try? JSONEncoder().encode(samples),
              let sealed = CryptoBox.encrypt(plaintext) else { return }
        try? sealed.write(to: fileURL, options: .atomic)
    }

    private func load() -> [[Float]] {
        guard let data = try? Data(contentsOf: fileURL),
              let plaintext = CryptoBox.decrypt(data),
              let decoded = try? JSONDecoder().decode([[Float]].self, from: plaintext)
        else { return [] }
        return decoded
    }
}
