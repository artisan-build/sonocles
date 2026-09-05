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

    /// Control-API credentials, edited in the popover.
    var authEnabled = CredentialStore.isEnabled
    var username = CredentialStore.username
    var password = CredentialStore.readPassword() ?? ""

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

    /// Credentials take effect on the next bind, because the HTTP server reads
    /// them when it is constructed. Saving while running is allowed and simply
    /// applies at next launch rather than silently doing nothing.
    func saveCredentials() {
        CredentialStore.save(username: username, password: password)
        authEnabled = CredentialStore.isEnabled
        status =
            authEnabled
            ? "Control API locked — restart to apply"
            : "Control API open — restart to apply"
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
