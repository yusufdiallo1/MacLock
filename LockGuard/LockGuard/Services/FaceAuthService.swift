//
//  FaceAuthService.swift
//  LockGuard
//
//  Front-camera face gate built on AVFoundation + Vision.
//
//  IMPORTANT — what this is and isn't:
//  Apple exposes no public face-*identity* embedding API (VNRecognizeAnimals
//  classifies cats/dogs; the face-print APIs are private). So the "feature
//  vector" here is derived purely from Vision's 2D face landmarks
//  (VNDetectFaceLandmarksRequest) — normalized geometric ratios between the
//  eyes, nose, mouth and jaw. Comparison is cosine similarity against the
//  enrolled vector.
//
//  This is a PRESENCE / rough-match gate, not hardened biometric security:
//  landmark geometry cannot reliably tell similar faces apart the way a deep
//  embedding can. It's appropriate for "is this roughly the owner" — treat it
//  accordingly and never as a substitute for a password.
//
//  The enrolled vector is stored encrypted in the Keychain
//  (kSecClassGenericPassword). A sensitivity slider (0.5 permissive … 0.95
//  strict) lives in UserDefaults and sets the match threshold. If no camera is
//  available the service degrades to `.unavailable` rather than failing hard.
//

@preconcurrency import AVFoundation
import Vision
import Combine
import simd

@MainActor
final class FaceAuthService: NSObject, ObservableObject {
    static let shared = FaceAuthService()

    // MARK: - State

    enum State: Equatable {
        case idle
        case enrolling(progress: Int, total: Int)
        case authenticating
        case success
        case failed(reason: String)
        /// No usable camera — the caller should fall back to another unlock path.
        case unavailable
    }

    @Published private(set) var state: State = .idle
    /// Whether an enrollment exists (drives "Set up Face Unlock" vs "Re-enroll").
    @Published private(set) var isEnrolled: Bool = false

    /// While true (set by the emergency kill switch), face unlock is disabled —
    /// `authenticate` refuses immediately so only the master password unlocks.
    @Published private(set) var isKillSwitchActive: Bool = false

    /// The capture session, exposed so the auth overlay can show a live preview
    /// (AVCaptureVideoPreviewLayer). Only for display — do not mutate.
    var captureSession: AVCaptureSession { session }

    /// Match strictness. 0.5 = permissive, 0.95 = strict. Persisted.
    @Published var sensitivity: Double {
        didSet {
            let clamped = min(0.95, max(0.5, sensitivity))
            if clamped != sensitivity { sensitivity = clamped; return }
            UserDefaults.standard.set(sensitivity, forKey: Self.sensitivityKey)
        }
    }

    // MARK: - Config

    private static let sensitivityKey = "LockGuard.faceSensitivity.v1"
    private static let keychainService = "com.lockguard.faceauth"
    private static let keychainAccount = "enrolled-face-vector-v1"
    private static let enrollmentFrameCount = 5
    /// A wrong/absent face fails after this long rather than sampling forever.
    private static let authTimeout: TimeInterval = 8

    // MARK: - Capture

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sampleQueue = DispatchQueue(label: "com.lockguard.faceauth.samples")
    private var configured = false

    // MARK: - Runtime accumulators

    /// Per-frame vectors captured during the current enrollment. Their mean and
    /// per-feature standard deviation become the stored profile.
    private var enrollmentVectors: [[Float]] = []
    /// The enrolled profile (loaded from Keychain), if any.
    private var enrolledProfile: FaceProfile?
    /// Called once when the current authenticate attempt resolves.
    private var authResolution: ((Bool) -> Void)?
    /// Deadline for the current authenticate attempt; a wrong/absent face fails
    /// rather than streaming the camera forever.
    private var authDeadline: Date?

    /// An enrolled face: the mean landmark vector and per-feature standard
    /// deviation, so authentication can z-score live features against the
    /// enrolled distribution (see `FaceAuthService.matches`).
    struct FaceProfile: Equatable {
        var mean: [Float]
        var std: [Float]
    }

    private override init() {
        let stored = UserDefaults.standard.object(forKey: Self.sensitivityKey) as? Double
        self.sensitivity = stored.map { min(0.95, max(0.5, $0)) } ?? 0.75
        super.init()
        self.enrolledProfile = Self.loadEnrolledProfile()
        self.isEnrolled = enrolledProfile != nil
    }

    // MARK: - Public API

    /// Begin enrollment: capture `enrollmentFrameCount` good frames, build a
    /// mean+std profile, and store it in the Keychain. Failure reasons surface
    /// through `state`. Requests camera access first if not yet determined.
    func enroll() {
        withCameraReady { [weak self] ready in
            guard let self else { return }
            guard ready else { self.state = .unavailable; return }
            self.enrollmentVectors.removeAll()
            self.state = .enrolling(progress: 0, total: Self.enrollmentFrameCount)
            self.startSessionIfNeeded()
        }
    }

    /// Begin an authentication attempt. `completion(true)` on a match. The
    /// service stops the camera and settles on `.success`/`.failed`. A wrong or
    /// absent face fails at the timeout rather than streaming forever.
    func authenticate(completion: @escaping (Bool) -> Void) {
        guard !isKillSwitchActive else {
            state = .failed(reason: "Face unlock is disabled. Enter your password.")
            completion(false); return
        }
        guard enrolledProfile != nil else {
            state = .failed(reason: "No face is enrolled yet.")
            completion(false); return
        }
        withCameraReady { [weak self] ready in
            guard let self else { completion(false); return }
            guard ready else { self.state = .unavailable; completion(false); return }
            self.authResolution = completion
            self.authDeadline = Date().addingTimeInterval(Self.authTimeout)
            self.state = .authenticating
            self.startSessionIfNeeded()
        }
    }

    /// Enable/disable face unlock (driven by the emergency kill switch). When
    /// activated, any in-flight attempt is cancelled.
    func setKillSwitch(active: Bool) {
        isKillSwitchActive = active
        if active { cancel() }
    }

    /// Stop the camera and return to idle without resolving an attempt.
    func cancel() {
        stopSession()
        authDeadline = nil
        if case .authenticating = state { authResolution?(false); authResolution = nil }
        state = .idle
    }

    /// Remove the enrolled face from the Keychain.
    func removeEnrollment() {
        Self.deleteEnrolledProfile()
        enrolledProfile = nil
        isEnrolled = false
        if case .success = state {} else { state = .idle }
    }

    // MARK: - Camera availability & authorization

    /// True only if a camera device exists *and* access is authorized.
    private var cameraAvailable: Bool {
        cameraDeviceExists
            && AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    private var cameraDeviceExists: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
            || AVCaptureDevice.default(for: .video) != nil
    }

    /// Ensure the camera exists and is authorized, prompting for access if the
    /// status is undetermined, then call back on the main actor. `false` means
    /// the caller should treat the camera as unavailable.
    private func withCameraReady(_ done: @escaping (Bool) -> Void) {
        guard cameraDeviceExists else { done(false); return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            done(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in done(granted) }
            }
        case .denied, .restricted:
            done(false)
        @unknown default:
            done(false)
        }
    }

    // MARK: - Session lifecycle

    private func startSessionIfNeeded() {
        configureIfNeeded()
        guard configured else { state = .unavailable; return }
        guard !session.isRunning else { return }
        // AVCaptureSession start blocks; keep it off the main actor.
        let session = self.session
        sampleQueue.async { session.startRunning() }
    }

    private func stopSession() {
        guard configured, session.isRunning else { return }
        let session = self.session
        sampleQueue.async { session.stopRunning() }
    }

    private func configureIfNeeded() {
        guard !configured else { return }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            configured = false
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .medium
        if session.canAddInput(input) { session.addInput(input) }

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        session.commitConfiguration()

        configured = session.inputs.isEmpty == false && session.outputs.isEmpty == false
    }

    // MARK: - Frame handling (called on sampleQueue, hops to main actor)

    /// Process one detected face vector. Runs on the main actor, which
    /// serializes it — the enrollment counter can't overshoot 5.
    private func handle(vector: [Float]) {
        switch state {
        case .enrolling:
            // Defensive: only count while genuinely enrolling and under the cap.
            guard enrollmentVectors.count < Self.enrollmentFrameCount else { return }
            enrollmentVectors.append(vector)
            let n = enrollmentVectors.count
            state = .enrolling(progress: n, total: Self.enrollmentFrameCount)
            if n >= Self.enrollmentFrameCount { finishEnrollment() }

        case .authenticating:
            // Time out a wrong/absent face instead of streaming forever.
            if let deadline = authDeadline, Date() > deadline {
                stopSession()
                authDeadline = nil
                state = .failed(reason: "Face not recognized.")
                authResolution?(false); authResolution = nil
                return
            }
            guard let profile = enrolledProfile else { return }
            if Self.matches(vector, to: profile, sensitivity: sensitivity) {
                stopSession()
                authDeadline = nil
                state = .success
                authResolution?(true); authResolution = nil
            }
            // Below threshold: keep sampling until match, timeout, or cancel().

        default:
            break
        }
    }

    private func finishEnrollment() {
        stopSession()
        guard let profile = Self.buildProfile(enrollmentVectors) else {
            state = .failed(reason: "Couldn't read your face clearly. Try again in better light.")
            return
        }
        enrollmentVectors.removeAll()
        if Self.storeEnrolledProfile(profile) {
            enrolledProfile = profile
            isEnrolled = true
            state = .success
        } else {
            state = .failed(reason: "Couldn't securely save your face. Try again.")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension FaceAuthService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Vision runs synchronously here on the sample queue.
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
        do {
            try handler.perform([request])
        } catch {
            return
        }

        guard
            let face = request.results?
                .max(by: { $0.boundingBox.area < $1.boundingBox.area }),
            let vector = Self.landmarkVector(from: face)
        else { return }

        Task { @MainActor [weak self] in self?.handle(vector: vector) }
    }
}

// MARK: - Landmark → feature vector (pure geometry)
//
// These are `nonisolated` pure functions — no actor state — so the capture
// delegate can call them directly off the sample queue.

private extension FaceAuthService {

    /// Turn a face observation's 2D landmarks into a rotation/scale-normalized
    /// geometric feature vector. `nil` if the landmarks are too sparse to use.
    nonisolated static func landmarkVector(from face: VNFaceObservation) -> [Float]? {
        guard let lm = face.landmarks else { return nil }

        // Anchor on the eyes: their midpoints define scale (inter-ocular
        // distance) and in-plane rotation, so the vector is invariant to how
        // far/tilted the face is.
        guard
            let leftEye = lm.leftEye?.normalizedPoints, !leftEye.isEmpty,
            let rightEye = lm.rightEye?.normalizedPoints, !rightEye.isEmpty
        else { return nil }

        let leftCenter = centroid(leftEye)
        let rightCenter = centroid(rightEye)
        let interOcular = distance(leftCenter, rightCenter)
        guard interOcular > 1e-4 else { return nil }

        // Collect a stable set of region centroids; ratios between them, scaled
        // by inter-ocular distance, form the feature vector.
        var anchors: [CGPoint] = [leftCenter, rightCenter]
        func add(_ region: VNFaceLandmarkRegion2D?) {
            if let pts = region?.normalizedPoints, !pts.isEmpty {
                anchors.append(centroid(pts))
            } else {
                anchors.append(CGPoint(x: CGFloat.nan, y: CGFloat.nan)) // keep vector length stable
            }
        }
        add(lm.nose)
        add(lm.noseCrest)
        add(lm.outerLips)
        add(lm.innerLips)
        add(lm.medianLine)
        add(lm.leftEyebrow)
        add(lm.rightEyebrow)
        add(lm.faceContour)

        // Pairwise normalized distances between every anchor pair → the vector.
        // Missing regions (NaN) contribute a fixed 0 so vector length is stable.
        var v: [Float] = []
        for i in 0..<anchors.count {
            for j in (i + 1)..<anchors.count {
                let a = anchors[i], b = anchors[j]
                if a.x.isNaN || b.x.isNaN {
                    v.append(0)
                } else {
                    v.append(Float(distance(a, b) / interOcular))
                }
            }
        }
        return v.isEmpty ? nil : v
    }

    nonisolated static func centroid(_ pts: [CGPoint]) -> CGPoint {
        guard !pts.isEmpty else { return .zero }
        let sum = pts.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(pts.count), y: sum.y / CGFloat(pts.count))
    }

    nonisolated static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Build a mean + per-feature standard-deviation profile from the enrollment
    /// frames. std is the spread of each landmark ratio across the 5 captures;
    /// authentication z-scores against it so features vary in their own units.
    nonisolated static func buildProfile(_ vectors: [[Float]]) -> FaceProfile? {
        guard let first = vectors.first, !first.isEmpty else { return nil }
        let usable = vectors.filter { $0.count == first.count }
        guard usable.count >= 2 else { return nil }   // need spread for a std

        let dim = first.count
        var mean = [Float](repeating: 0, count: dim)
        for vec in usable { for i in 0..<dim { mean[i] += vec[i] } }
        for i in 0..<dim { mean[i] /= Float(usable.count) }

        var std = [Float](repeating: 0, count: dim)
        for vec in usable {
            for i in 0..<dim {
                let d = vec[i] - mean[i]
                std[i] += d * d
            }
        }
        // Population std, floored so a feature that happened not to vary across
        // 5 frames doesn't explode the z-score at auth time.
        for i in 0..<dim {
            std[i] = max((std[i] / Float(usable.count)).squareRoot(), 0.01)
        }
        return FaceProfile(mean: mean, std: std)
    }

    /// Does a live vector match the enrolled profile? We compute the RMS
    /// z-score distance — how many standard deviations, on average, the live
    /// features sit from the enrolled mean — and accept when it's under a
    /// threshold derived from the sensitivity slider.
    ///
    /// Cosine similarity is deliberately NOT used: these vectors are all
    /// positive distance ratios, so any two faces point in nearly the same
    /// direction and cosine barely discriminates. Z-scored deviation measures
    /// per-feature difference in the enrolled distribution's own units, which is
    /// what actually separates faces here.
    nonisolated static func matches(
        _ vector: [Float],
        to profile: FaceProfile,
        sensitivity: Double
    ) -> Bool {
        guard vector.count == profile.mean.count, !vector.isEmpty else { return false }

        var sumSq: Float = 0
        for i in vector.indices {
            let z = (vector[i] - profile.mean[i]) / profile.std[i]
            sumSq += z * z
        }
        let rmsZ = (sumSq / Float(vector.count)).squareRoot()

        // Map sensitivity (0.5 permissive … 0.95 strict) to an allowed RMS-z.
        // Permissive tolerates ~3σ of average deviation; strict ~1σ.
        let maxZ = Float(3.5 - (sensitivity - 0.5) * (2.5 / 0.45))
        return rmsZ <= maxZ
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}

// MARK: - Keychain storage (encrypted at rest)

private extension FaceAuthService {

    /// Serialize a profile as: [Int32 dim][dim × Float mean][dim × Float std].
    static func profileData(_ profile: FaceProfile) -> Data {
        var data = Data()
        var dim = Int32(profile.mean.count)
        withUnsafeBytes(of: &dim) { data.append(contentsOf: $0) }
        profile.mean.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        profile.std.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }

    static func profile(from data: Data) -> FaceProfile? {
        let header = MemoryLayout<Int32>.size
        guard data.count >= header else { return nil }
        // Copy out (never bindMemory on Data's bytes — alignment isn't
        // guaranteed and misaligned binds are undefined behavior).
        var dim: Int32 = 0
        _ = withUnsafeMutableBytes(of: &dim) { data.copyBytes(to: $0, from: 0..<header) }
        guard dim > 0 else { return nil }
        let n = Int(dim)
        let floatBytes = n * MemoryLayout<Float>.stride
        guard data.count == header + 2 * floatBytes else { return nil }

        func readFloats(at offset: Int) -> [Float] {
            var out = [Float](repeating: 0, count: n)
            out.withUnsafeMutableBytes { dst in
                _ = data.copyBytes(to: dst, from: offset..<(offset + floatBytes))
            }
            return out
        }
        let mean = readFloats(at: header)
        let std = readFloats(at: header + floatBytes)
        return FaceProfile(mean: mean, std: std)
    }

    static func storeEnrolledProfile(_ profile: FaceProfile) -> Bool {
        let data = profileData(profile)
        // Remove any prior entry first so SecItemAdd can't collide.
        deleteEnrolledProfile()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            // Encrypted at rest, only readable on this device while unlocked.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func loadEnrolledProfile() -> FaceProfile? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return profile(from: data)
    }

    static func deleteEnrolledProfile() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
