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
    /// The current utterance — the partial being revised, until a final
    /// settles it into `transcript`.
    var text = ""
    /// Settled utterances, oldest first, kept to what the pane can show. The
    /// protocol's `text` is the utterance and not the session, so a running
    /// transcript is something a consumer accumulates — this popover is a
    /// consumer like any other.
    var transcript: [String] = []
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

        // The segmented control follows the service, not the click: a switch
        // made over POST /engine moves it too, which it did not before.
        service.onEngineChanged = { [weak self] choice in
            Task { @MainActor in self?.engine = choice }
        }

        service.onFrame = { [weak self] hypothesis, frame, nanos in
            Task { @MainActor in
                guard let self else { return }
                // A partial revises the live line; a final settles it, and
                // the next partial opens a new one.
                if hypothesis.isFinal {
                    self.transcript.append(hypothesis.text)
                    if self.transcript.count > Self.transcriptKept {
                        self.transcript.removeFirst(self.transcript.count - Self.transcriptKept)
                    }
                    self.text = ""
                } else {
                    self.text = hypothesis.text
                }
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

    /// Settled lines kept — more than the pane shows, since a settled line
    /// can wrap. The pane is a window over the end of this, not all of it.
    static let transcriptKept = 8

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

    /// The same path as `POST /engine`. Switching engine restarts capture:
    /// models differ, and a half-swapped pipeline would report numbers
    /// belonging to neither. `engine` is set from the service's callback,
    /// not here, so the control shows what the service has and nothing else.
    func use(_ choice: EngineChoice) {
        guard let service else {
            engine = choice
            return
        }
        do {
            try service.use(engine: choice)
        } catch {
            status = error.localizedDescription
        }
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
        transcript = []
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
