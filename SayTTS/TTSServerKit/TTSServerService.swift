import Darwin
import Foundation
import Hummingbird
import NIOCore
import ServiceLifecycle

/// Lifecycle state of an embedded TTS server.
public enum TTSServerState: Sendable, Equatable {
    case stopped
    case starting
    case running
    case stopping
    case failed(String)

    public var isRunning: Bool { self == .running }

    public var isBusy: Bool { self == .starting || self == .stopping }
}

/// An embeddable, start/stoppable TTS HTTP server.
///
/// The SayTTS menu bar app owns one of these and drives it from its UI;
/// the CLI runs one to completion.
public actor TTSServerService {
    public private(set) var state: TTSServerState = .stopped

    private let configuration: TTSServerConfiguration
    private var serviceGroup: ServiceGroup?
    private var runTask: Task<Void, Never>?

    public init(configuration: TTSServerConfiguration) {
        self.configuration = configuration
    }

    /// The configuration this service was created with.
    public var currentConfiguration: TTSServerConfiguration { configuration }

    /// Starts listening. Returns once the server is accepting connections,
    /// or throws if the address could not be bound.
    public func start() async throws {
        guard state == .stopped || hasFailed() else { return }
        state = .starting

        let builder = TTSServerRouter(configuration: configuration)
        let router = builder.makeRouter(token: configuration.token)

        // One channel carries the first outcome: the server bound, or it failed.
        let events = AsyncStream<Result<Void, any Error>>.makeStream()

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(configuration.host, port: configuration.port),
                serverName: "SayTTS"
            ),
            onServerRunning: { _ in
                events.continuation.yield(.success(()))
                events.continuation.finish()
            }
        )

        // A service group without signal handlers: the host app decides when to stop.
        let group = ServiceGroup(
            configuration: .init(
                services: [app],
                gracefulShutdownSignals: [],
                cancellationSignals: [],
                logger: app.logger
            )
        )
        serviceGroup = group

        runTask = Task { [weak self] in
            do {
                try await group.run()
                // The group returns only after the server has fully shut down.
                events.continuation.yield(.failure(TTSServerError.serverExitedUnexpectedly))
                events.continuation.finish()
                await self?.markStopped()
            } catch {
                events.continuation.yield(.failure(error))
                events.continuation.finish()
            }
        }

        // Wait for the first outcome: a bound listener, or a bind failure.
        for await event in events.stream {
            switch event {
            case .success:
                state = .running
            case .failure(let error):
                // A shutdown requested while starting is not a failure.
                guard state == .starting else { return }
                await shutdownRunTask()
                serviceGroup = nil
                let reason = Self.describe(error, configuration: configuration)
                state = .failed(reason)
                // Surface the same readable reason to the caller.
                throw TTSServerError.startupFailed(reason)
            }
            // The continuation is finished after the first event, so this ends the loop.
        }

        // The stream ended without an outcome: the server never came up.
        if state == .starting {
            state = .failed(TTSServerError.serverExitedUnexpectedly.errorDescription ?? "Server stopped.")
        }
    }

    /// Stops the server and waits for the listener to close.
    public func stop() async {
        guard state != .stopped else { return }
        state = .stopping
        await shutdownRunTask()
        serviceGroup = nil
        state = .stopped
    }

    private func hasFailed() -> Bool {
        if case .failed = state { return true }
        return false
    }

    private func markStopped() {
        // Do not clobber a failure that was already recorded.
        guard case .stopping = state else { return }
        state = .stopped
    }

    private func shutdownRunTask() async {
        guard let task = runTask else { return }
        // A graceful shutdown lets the listener drain in-flight requests; the
        // cancel is only a backstop so `stop()` can never hang.
        await serviceGroup?.triggerGracefulShutdown()
        await task.value
        runTask = nil
    }

    /// Human-readable failure text for the UI and the CLI banner.
    ///
    /// Bind failures arrive as a bare `IOError` carrying only an `errno`, which is
    /// not something worth showing a user, so the common cases are translated.
    private static func describe(_ error: any Error, configuration: TTSServerConfiguration) -> String {
        if let ioError = error as? IOError {
            switch ioError.errnoCode {
            case EADDRINUSE:
                return "Port \(configuration.port) is already in use. Stop the other server or pick a different port."
            case EACCES:
                return "Permission denied binding port \(configuration.port). Ports below 1024 need elevated privileges."
            case EADDRNOTAVAIL:
                return "\(configuration.host) is not an address this machine can bind to."
            case ENETUNREACH, EHOSTUNREACH:
                return "\(configuration.host) is not reachable from this machine."
            default:
                break
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
