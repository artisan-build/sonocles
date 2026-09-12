import AppKit
import Foundation
import Observation
import SonoclesCore

/// What the popover shows.
///
/// A thin observable shell over `Service`. Deliberately thin: the service is
/// the same object the CLI drives and the HTTP API controls, so anything clever
/// added here would be behaviour the measurements never saw and the API cannot
/// reach.
///
/// The service is created once and its sockets stay up for the life of the app.
/// That is what lets `POST /start` work when the popover says "Idle" — and it
/// is the fix for a bug where stopping capture orphaned the listeners, leaving
/// ports bound to a deallocated server that accepted connections and answered
/// nothing.
@MainActor
@Observable
final class SidecarModel {
    /// One model for the process. The app delegate binds sockets at launch and
    /// the popover attaches to the same instance whenever it is opened.
    static let shared = SidecarModel()

    var running = false
    var levelDb: Double = -120
    var heldDb: Double = -120
    var text = ""
    var lagMs: Int?
    var gapMs: Int?
    var status = "Idle"
    var engine: EngineChoice = .fluid160

    /// Model download and compilation, before listening can begin. Nil once
    /// the models are resident, which is every launch after the first.
    var preparation: Preparation?

    /// The bearer token every route is behind, for the popover to show and
    /// copy. Read from the service once the sockets are bound; nil until then.
    var token: String?
    /// The Control API section open in the popover.
    var pairingOpen = false
    /// The token shown in full, or masked to its ends.
    var tokenShown = false
    /// Rotate is two clicks: the first arms it, the second does it. A
    /// rotation cuts off every other paired client, so it is not one slip.
    var rotateArmed = false

    private var service: Service?
    private var lastArrival: UInt64?
    private var decayTimer: Timer?

    var engineLabel: String { service?.engineName ?? engine.label }

    /// Bring the sockets up once, at launch. Capture stays off until asked —
    /// by the button, or by `POST /start`.
    func bind() {
        guard service == nil else { return }

        let service = Service(config: Service.Config(sidecar: .init(engine: engine))) {
            [weak self] message in
            Task { @MainActor in self?.status = message }
        }

        service.onLevel = { [weak self] db in
            Task { @MainActor in self?.levelDb = db }
        }

        service.onPreparation = { [weak self] preparation in
            Task { @MainActor in
                self?.preparation = preparation.isFinished ? nil : preparation
            }
        }

        service.onListeningChanged = { [weak self] listening in
            Task { @MainActor in
                self?.running = listening
                if listening { self?.startDecay() } else { self?.clearLive() }
            }
        }

        service.onFrame = { [weak self] hypothesis, frame, nanos in
            Task { @MainActor in
                guard let self else { return }
                self.text = hypothesis.text
                self.lagMs = frame.lagMs
                if let last = self.lastArrival {
                    self.gapMs = Int((nanos &- last) / 1_000_000)
                }
                self.lastArrival = nanos
            }
        }

        do {
            try service.bind()
            self.service = service
            token = service.token
            status = "Idle — sockets up"
        } catch {
            status = "Could not bind: \(error.localizedDescription)"
        }
    }

    func start() {
        bind()
        status = "Starting…"
        service?.startListening()
    }

    func stop() {
        service?.stopListening()
    }

    func shutdown() {
        service?.shutdown()
        service = nil
    }

    /// Switching engine restarts capture: models differ, and a half-swapped
    /// pipeline would report numbers belonging to neither.
    func use(_ choice: EngineChoice) {
        guard choice != engine else { return }

        engine = choice
        service?.use(engine: choice)
    }

    /// Where the token lives, so the popover can say so.
    var tokenFile: String { TokenStore.standard.fileURL.path }

    /// The token, masked to its ends: enough to compare, not enough to use.
    var maskedToken: String? {
        guard let token, token.count > 12 else { return token }
        return "\(token.prefix(6))…\(token.suffix(6))"
    }

    func copyToken() {
        guard let token else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        status = "Token copied"
    }

    /// Same as `POST /token/rotate`, in-process: the file is rewritten and the
    /// old token is dead for every request after this. Every other paired
    /// client has to read the file again; that is what rotation is for, and
    /// why it takes two clicks.
    func rotateToken() {
        guard rotateArmed else {
            rotateArmed = true
            Task {
                try? await Task.sleep(for: .seconds(6))
                rotateArmed = false
            }
            return
        }
        rotateArmed = false
        do {
            token = try service?.rotateToken()
            status = "Token rotated — paired clients must re-read the file"
        } catch {
            status = "Could not rotate: \(error.localizedDescription)"
        }
    }

    private func clearLive() {
        preparation = nil
        text = ""
        lagMs = nil
        gapMs = nil
        lastArrival = nil
        levelDb = -120
        heldDb = -120
        decayTimer?.invalidate()
        decayTimer = nil
    }

    /// Rise instantly, fall at ~40 dB/sec — what every hardware meter does, and
    /// the difference between "something is happening" and a legible level.
    private func startDecay() {
        decayTimer?.invalidate()
        decayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.heldDb = max(self.levelDb, self.heldDb - 40.0 / 30)
            }
        }
    }
}
