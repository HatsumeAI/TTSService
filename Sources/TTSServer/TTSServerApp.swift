import Darwin
import Foundation
import TTSServerKit

/// Standalone entry point for running the TTS server as a launchd service or via `swift run`.
@main
struct TTSServerApp {
    static func main() async throws {
        let configuration = TTSServerConfiguration.fromEnvironment()
        let service = TTSServerService(configuration: configuration)

        print("SayTTS server listening on \(configuration.displayURL)")
        if configuration.requiresAuthentication {
            print("Bearer token authentication is enabled.")
        }
        if configuration.host == TTSServerConfiguration.allInterfacesHost {
            print("Warning: serving on all interfaces. Anyone on the network can reach this server.")
        }

        try await service.start()

        // Stay alive until a termination signal arrives, then shut the listener down cleanly
        // so in-flight requests finish before the process exits.
        await TerminationSignal.wait()
        print("\nShutting down…")
        await service.stop()
    }
}

/// Bridges POSIX termination signals into async code.
///
/// The first SIGTERM/SIGINT resumes the wait; a second one is left to the default
/// disposition so an impatient operator can always force the process down.
enum TerminationSignal {
    static func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let box = SignalSources()

            for signalNumber in [SIGTERM, SIGINT] {
                // Step aside so the dispatch source observes the signal instead of the
                // process dying on the default disposition.
                signal(signalNumber, SIG_IGN)

                let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
                source.setEventHandler {
                    if box.claimSignal() {
                        continuation.resume()
                    }
                }
                box.add(source)
                source.resume()
            }
        }
    }

    /// Owns the signal sources for the process lifetime and hands out a one-shot claim.
    private final class SignalSources: @unchecked Sendable {
        private let lock = NSLock()
        private var sources: [any DispatchSourceSignal] = []
        private var claimed = false

        func add(_ source: any DispatchSourceSignal) {
            lock.lock()
            defer { lock.unlock() }
            sources.append(source)
        }

        /// Returns true for the first signal only, so the continuation resumes once.
        func claimSignal() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}
