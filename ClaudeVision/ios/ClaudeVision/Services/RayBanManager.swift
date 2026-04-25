import Combine
import Foundation
import MWDATCamera
import MWDATCore
import UIKit

@MainActor
class RayBanManager: NSObject, ObservableObject, FrameSource {

  // MARK: - FrameSource Protocol

  @Published var latestFrame: Data?
  @Published var latestImage: UIImage?
  @Published private(set) var isRunning: Bool = false
  @Published private(set) var connectionStatus: FrameSourceStatus = .disconnected
  @Published var frameCount: Int = 0

  let sourceType: FrameSourceType = .rayBan

  // MARK: - State

  @Published var glassesName: String = "Not Connected"
  @Published var hasActiveDevice: Bool = false
  @Published var registrationState: String = "unregistered"
  @Published var isRegistered: Bool = false

  // DAT SDK
  private var deviceSession: DeviceSession?
  private var streamSession: StreamSession?
  private var deviceSelector: AutoDeviceSelector?
  private var stateToken: AnyListenerToken?
  private var frameToken: AnyListenerToken?
  private var errorToken: AnyListenerToken?
  private var deviceMonitorTask: Task<Void, Never>?
  private var registrationTask: Task<Void, Never>?

  private var frameInterval: TimeInterval = 1.0
  private var jpegQuality: CGFloat = 0.5
  private var lastCaptureTime: Date = .distantPast

  // MARK: - Configuration

  func configure(frameInterval: TimeInterval = 1.0, jpegQuality: CGFloat = 0.5) {
    self.frameInterval = frameInterval
    self.jpegQuality = jpegQuality
  }

  // MARK: - Registration (MUST complete before streaming)

  func startMonitoringRegistration() {
    let wearables = Wearables.shared
    registrationTask = Task { @MainActor in
      for await state in wearables.registrationStateStream() {
        switch state {
        case .registered:
          self.registrationState = "registered"
          self.isRegistered = true
          print("[RayBan] Registration complete")
        case .registering:
          self.registrationState = "registering"
          print("[RayBan] Registration in progress...")
        case .available, .unavailable:
          self.registrationState = "unregistered"
          self.isRegistered = false
          print("[RayBan] Not registered")
        @unknown default:
          break
        }
      }
    }

    // Check current state
    let currentState = wearables.registrationState
    switch currentState {
    case .registered:
      isRegistered = true
      registrationState = "registered"
    case .registering:
      registrationState = "registering"
    case .available, .unavailable:
      registrationState = "unregistered"
    @unknown default:
      break
    }
  }

  func register() async {
    guard !isRegistered else {
      print("[RayBan] Already registered")
      return
    }

    do {
      print("[RayBan] Starting registration with Meta AI...")
      connectionStatus = .connecting
      try await Wearables.shared.startRegistration()
    } catch {
      print("[RayBan] Registration error: \(error)")
      connectionStatus = .error("Registration failed: \(error.localizedDescription)")
    }
  }

  // MARK: - FrameSource Implementation

  func start() throws {
    guard !isRunning else { return }

    // Re-check registration state directly from SDK
    let currentState = Wearables.shared.registrationState
    if currentState == .registered {
      isRegistered = true
      registrationState = "registered"
    }

    guard isRegistered else {
      print("[RayBan] Not registered (state: \(currentState)) — starting registration first")
      connectionStatus = .error("Tap 'Connect Glasses' in Settings to register with Meta AI first")
      Task { await register() }
      return
    }

    connectionStatus = .connecting
    print("[RayBan] Waiting for an eligible device...")

    let wearables = Wearables.shared
    let selector = AutoDeviceSelector(wearables: wearables)
    self.deviceSelector = selector

    // Stream at 30fps, high resolution (720x1280)
    let config = StreamSessionConfig(
      videoCodec: .raw,
      resolution: .high,
      frameRate: 30
    )

    // MWDAT 0.6 requires this exact order: permission → createSession →
    // deviceSession.start() → addStream → stream.start(). addStream silently
    // returns nil if any prerequisite is unmet. Wait for AutoDeviceSelector
    // to surface a device first to avoid `noEligibleDevice`.
    deviceMonitorTask = Task { @MainActor [weak self] in
      var sessionStarted = false
      for await device in selector.activeDeviceStream() {
        guard let self else { return }
        self.hasActiveDevice = device != nil
        if device != nil {
          self.glassesName = "Ray-Ban Meta"
          print("[RayBan] Device active")
          if !sessionStarted {
            sessionStarted = true
            await self.beginStreamSession(wearables: wearables, selector: selector, config: config)
          }
        } else {
          self.glassesName = "No Device"
          print("[RayBan] No active device")
        }
      }
    }
  }

  private func beginStreamSession(
    wearables: any WearablesInterface,
    selector: AutoDeviceSelector,
    config: StreamSessionConfig
  ) async {
    // Step 1: Camera permission. Must be granted BEFORE addStream or
    // addStream returns nil silently.
    do {
      print("[RayBan] Checking camera permission...")
      let status = try await wearables.checkPermissionStatus(.camera)
      print("[RayBan] Camera permission status: \(status)")
      if status != .granted {
        print("[RayBan] Requesting camera permission (will open Meta AI)...")
        let result = try await wearables.requestPermission(.camera)
        print("[RayBan] Permission result: \(result)")
        if result != .granted {
          print("[RayBan] Camera permission denied — proceeding (Developer Mode may bypass)")
        }
      }
    } catch {
      print("[RayBan] Permission error: \(error) — proceeding anyway")
    }

    // Step 2: Create the device session.
    let deviceSession: DeviceSession
    do {
      print("[RayBan] Creating device session...")
      deviceSession = try wearables.createSession(deviceSelector: selector)
      self.deviceSession = deviceSession
    } catch {
      print("[RayBan] Failed to create device session: \(error)")
      connectionStatus = .error("Failed to create session: \(error.localizedDescription)")
      return
    }

    // Step 3: Start the device session BEFORE adding capabilities.
    do {
      print("[RayBan] Starting device session...")
      try deviceSession.start()
    } catch {
      print("[RayBan] Failed to start device session: \(error)")
      connectionStatus = .error("Failed to start session: \(error.localizedDescription)")
      return
    }

    // Step 4: Add the stream capability. Now safe — permission granted and
    // device session started.
    let session: StreamSession
    do {
      guard let stream = try deviceSession.addStream(config: config) else {
        print("[RayBan] addStream returned nil — permission/state mismatch")
        connectionStatus = .error("Camera not available. Check Meta AI permission.")
        return
      }
      session = stream
      self.streamSession = session
    } catch {
      print("[RayBan] addStream threw: \(error)")
      connectionStatus = .error("Failed to add stream: \(error.localizedDescription)")
      return
    }

    // Step 5: Listeners — install before session.start() so we don't miss
    // the first frames or state transitions.
    stateToken = session.statePublisher.listen { [weak self] (state: StreamSessionState) in
      Task { @MainActor [weak self] in
        guard let self else { return }
        print("[RayBan] State: \(state)")
        switch state {
        case .streaming:
          self.isRunning = true
          self.connectionStatus = .connected
        case .stopped:
          self.isRunning = false
          self.connectionStatus = .disconnected
        case .waitingForDevice:
          self.connectionStatus = .connecting
        case .starting:
          self.connectionStatus = .connecting
        case .stopping:
          self.connectionStatus = .connecting
        case .paused:
          self.connectionStatus = .connecting
        @unknown default:
          break
        }
      }
    }

    frameToken = session.videoFramePublisher.listen { [weak self] (videoFrame: VideoFrame) in
      Task { @MainActor [weak self] in
        guard let self else { return }
        guard let uiImage = videoFrame.makeUIImage() else { return }
        self.latestImage = uiImage
        self.frameCount += 1
        let now = Date()
        if now.timeIntervalSince(self.lastCaptureTime) >= self.frameInterval {
          self.lastCaptureTime = now
          if let jpegData = uiImage.jpegData(compressionQuality: self.jpegQuality) {
            self.latestFrame = jpegData
            print("[RayBan] Captured JPEG frame (\(jpegData.count) bytes)")
          }
        }
      }
    }

    errorToken = session.errorPublisher.listen { [weak self] (error: StreamSessionError) in
      Task { @MainActor [weak self] in
        guard let self else { return }
        let msg = self.formatError(error)
        print("[RayBan] Error: \(msg)")
        self.connectionStatus = .error(msg)
      }
    }

    // Step 6: Start the stream.
    print("[RayBan] Starting stream...")
    await session.start()
    print("[RayBan] Stream start() returned, state: \(session.state)")
  }

  func stop() {
    Task { await streamSession?.stop() }
    deviceSession?.stop()
    stateToken = nil
    frameToken = nil
    errorToken = nil
    deviceMonitorTask?.cancel()
    deviceMonitorTask = nil
    streamSession = nil
    deviceSession = nil
    deviceSelector = nil
    isRunning = false
    connectionStatus = .disconnected
    latestFrame = nil
    latestImage = nil
    glassesName = "Not Connected"
    hasActiveDevice = false
  }

  func consumeFrame() -> Data? {
    return latestFrame
  }

  func cleanup() {
    stop()
    registrationTask?.cancel()
    registrationTask = nil
  }

  // MARK: - Error Formatting

  private func formatError(_ error: StreamSessionError) -> String {
    switch error {
    case .deviceNotFound: return "Glasses not found. Power on and open hinges."
    case .deviceNotConnected: return "Glasses disconnected. Check Bluetooth."
    case .permissionDenied: return "Camera permission denied. Grant in Meta AI app Settings."
    case .hingesClosed: return "Open the glasses hinges to stream."
    case .thermalCritical: return "Glasses overheating. Streaming paused."
    case .timeout: return "Connection timed out. Try again."
    case .videoStreamingError: return "Video stream failed. Restart app."
    case .internalError: return "Internal SDK error. Restart app."
    @unknown default: return "Unknown glasses error."
    }
  }
}
