import Foundation
import Observation
import os

/// Runtime status of the embedded server, as shown in the UI.
enum ServerStatus: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case failed(String)

    var isRunning: Bool { self == .running }

    /// Settings are read-only while the server is starting, running or stopping.
    var locksSettings: Bool {
        switch self {
        case .stopped, .failed: false
        case .starting, .running, .stopping: true
        }
    }

    var title: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .running: "Running"
        case .stopping: "Stopping…"
        case .failed: "Failed"
        }
    }

    var detail: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Outcome of validating the port text field.
enum PortValidationResult: Equatable {
    case valid(Int)
    case invalid(String)

    var port: Int? {
        if case .valid(let value) = self { return value }
        return nil
    }

    var errorMessage: String? {
        if case .invalid(let message) = self { return message }
        return nil
    }
}

/// Validates the port text field.
enum PortValidator {
    static let range = 1...65535

    /// Keeps only digits, capped at the width of the largest valid port.
    static func sanitize(_ text: String) -> String {
        let digits = text.filter(\.isNumber)
        return String(digits.prefix(5))
    }

    /// Returns the parsed port, or a message explaining why the input is invalid.
    static func validate(_ text: String) -> PortValidationResult {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .invalid("Enter a port number.") }
        guard let value = Int(trimmed) else { return .invalid("Port must be a whole number.") }
        guard range.contains(value) else { return .invalid("Port must be between 1 and 65535.") }
        return .valid(value)
    }
}

/// One of the HTTP endpoints the server answers on, resolved against a base URL.
struct Endpoint: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case speech = "Speech"
        case transcription = "Transcription"

        var path: String {
            switch self {
            case .speech: "/v1/audio/speech"
            case .transcription: "/v1/audio/transcriptions"
            }
        }

        var symbol: String {
            switch self {
            case .speech: "waveform"
            case .transcription: "captions.bubble"
            }
        }
    }

    let id: Kind
    /// Always resolved: `endpoints` is empty while the port is invalid.
    let url: String
}

/// Observable state backing the menu bar UI: user settings plus the live server.
@MainActor
@Observable
final class AppModel {
    // MARK: Persisted settings

    /// Address the server binds to.
    var host: String {
        didSet { if host != oldValue { persist() } }
    }

    /// Port the server listens on, kept as text so the field can be mid-edit.
    var portText: String {
        didSet { if portText != oldValue { persist() } }
    }

    /// Optional bearer token, only applied when `requiresAuthentication` is on.
    var token: String {
        didSet { if token != oldValue { persist() } }
    }

    /// Whether clients must send `Authorization: Bearer <token>`.
    var requiresAuthentication: Bool {
        didSet { if requiresAuthentication != oldValue { persist() } }
    }

    /// Binds to all interfaces. Reflected into `host` so the field stays truthful.
    var serveOnLocalNetwork: Bool {
        didSet {
            guard serveOnLocalNetwork != oldValue else { return }
            host = serveOnLocalNetwork
                ? TTSServerConfiguration.allInterfacesHost
                : TTSServerConfiguration.defaultHost
            persist()
        }
    }

    /// Starts the server as soon as the app finishes launching.
    var autoStart: Bool {
        didSet { if autoStart != oldValue { persist() } }
    }

    // MARK: Runtime state

    private(set) var status: ServerStatus = .stopped
    private var service: TTSServerService?

    /// A menu bar app has no console, so transitions are logged to the unified log.
    private static let log = Logger(subsystem: "ai.roleswitch.tts", category: "server")

    /// Called on every status change so the status item can redraw itself.
    var onStatusChange: ((ServerStatus) -> Void)?

    /// Sets the status and records the transition for debugging.
    private func transition(to newStatus: ServerStatus) {
        Self.log.info("\(self.status.title, privacy: .public) -> \(newStatus.title, privacy: .public)")
        status = newStatus
        onStatusChange?(newStatus)
    }

    static let shared = AppModel()

    private let defaults: UserDefaults
    private enum Key {
        static let host = "settings.host"
        static let port = "settings.port"
        static let token = "settings.token"
        static let requiresAuthentication = "settings.requiresAuthentication"
        static let serveOnLocalNetwork = "settings.serveOnLocalNetwork"
        static let autoStart = "settings.autoStart"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedHost = defaults.string(forKey: Key.host)
        let storedNetwork = defaults.bool(forKey: Key.serveOnLocalNetwork)
        let resolvedHost = (storedHost?.isEmpty == false)
            ? storedHost!
            : (storedNetwork
                ? TTSServerConfiguration.allInterfacesHost
                : TTSServerConfiguration.defaultHost)

        let storedPort = defaults.object(forKey: Key.port) as? Int
        let storedToken = defaults.string(forKey: Key.token) ?? ""

        self.host = resolvedHost
        self.serveOnLocalNetwork = storedNetwork || resolvedHost == TTSServerConfiguration.allInterfacesHost
        self.portText = String(storedPort ?? TTSServerConfiguration.defaultPort)
        self.token = storedToken
        // Before the toggle existed a non-empty token was the only way to ask for
        // authentication, so keep honouring that on first launch after upgrading.
        self.requiresAuthentication = defaults.object(forKey: Key.requiresAuthentication) as? Bool
            ?? (storedToken.nonEmptyValue != nil)
        self.autoStart = defaults.bool(forKey: Key.autoStart)
    }

    // MARK: Derived values

    var isRunning: Bool { status.isRunning }

    /// True while the port field holds something that cannot be used.
    var portValidation: PortValidationResult { PortValidator.validate(portText) }

    /// The URL clients should call, once the port is valid.
    var serverURL: String? {
        guard let port = portValidation.port else { return nil }
        let displayHost = host == TTSServerConfiguration.allInterfacesHost
            ? TTSServerConfiguration.defaultHost
            : host
        return "http://\(displayHost):\(port)"
    }

    /// The token the server will actually enforce, if any.
    var effectiveToken: String? {
        requiresAuthentication ? token.nonEmptyValue : nil
    }

    /// Why authentication cannot be turned on yet, if it cannot.
    ///
    /// Requiring a token without setting one would serve every request anyway,
    /// so that combination is treated as a configuration mistake.
    var tokenValidationMessage: String? {
        guard requiresAuthentication else { return nil }
        guard effectiveToken == nil else { return nil }
        return "Enter a token, or turn off authentication."
    }

    /// The OpenAI-compatible endpoints this server exposes.
    var endpoints: [Endpoint] {
        guard let base = serverURL else { return [] }
        return Endpoint.Kind.allCases.map { Endpoint(id: $0, url: base + $0.path) }
    }

    var canStart: Bool {
        !status.locksSettings
            && portValidation.port != nil
            && tokenValidationMessage == nil
    }

    // MARK: Commands

    /// Starts serving, applying the current settings.
    func start() {
        guard !status.locksSettings else { return }
        guard let port = portValidation.port else {
            transition(to: .failed("Enter a valid port between 1 and 65535."))
            return
        }
        if let problem = tokenValidationMessage {
            transition(to: .failed(problem))
            return
        }

        transition(to: .starting)

        let configuration = TTSServerConfiguration(
            host: host,
            port: port,
            token: effectiveToken
        )
        let service = TTSServerService(configuration: configuration)
        self.service = service

        Task { [weak self] in
            do {
                try await service.start()
                self?.didStart()
            } catch {
                self?.didFail(error)
            }
        }
    }

    /// Stops serving and releases the port.
    func stop() {
        guard status.locksSettings else { return }
        transition(to: .stopping)

        guard let service else {
            transition(to: .stopped)
            return
        }

        Task { [weak self] in
            await service.stop()
            self?.service = nil
            self?.transition(to: .stopped)
        }
    }

    func toggle() {
        if status.locksSettings {
            stop()
        } else {
            start()
        }
    }

    /// Stops the server if it is up, so quitting does not drop in-flight requests.
    func shutdown() async {
        guard let service else { return }
        transition(to: .stopping)
        await service.stop()
        self.service = nil
        transition(to: .stopped)
    }

    // MARK: Callbacks

    private func didStart() {
        // `start` only returns once the listener is bound; failures throw. A stop
        // requested mid-start wins, so only claim "running" from the starting state.
        guard status == .starting else { return }
        transition(to: .running)
    }

    private func didFail(_ error: any Error) {
        // A stop requested mid-start is not a failure; `stop()` owns the final state.
        guard status == .starting else { return }
        service = nil
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        transition(to: .failed(message))
    }

    // MARK: Persistence

    private func persist() {
        defaults.set(host, forKey: Key.host)
        defaults.set(portValidation.port ?? TTSServerConfiguration.defaultPort, forKey: Key.port)
        defaults.set(token, forKey: Key.token)
        defaults.set(requiresAuthentication, forKey: Key.requiresAuthentication)
        defaults.set(serveOnLocalNetwork, forKey: Key.serveOnLocalNetwork)
        defaults.set(autoStart, forKey: Key.autoStart)
    }
}

extension String {
    /// The trimmed string, or nil when blank.
    var nonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
