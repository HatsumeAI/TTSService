import Foundation

/// Runtime configuration for the TTS HTTP server.
///
/// The CLI fills this from environment variables, while the SayTTS menu bar app
/// builds it from user-entered settings.
public struct TTSServerConfiguration: Sendable, Equatable {
    /// Host address to bind to.
    public var host: String
    /// Port number to listen on.
    public var port: Int
    /// Optional bearer token. When empty, requests are accepted without authentication.
    public var token: String?
    /// Path to the ffmpeg executable, required for mp3/opus output.
    public var ffmpegPath: String

    public init(host: String, port: Int, token: String? = nil, ffmpegPath: String = TTSServerConfiguration.defaultFFmpegPath) {
        self.host = host
        self.port = port
        self.token = token
        self.ffmpegPath = ffmpegPath
    }

    /// Resolves the ffmpeg executable, preferring `FFMPEG_PATH` then common install locations.
    public static func resolveFFmpegPath() -> String {
        if let configured = ProcessInfo.processInfo.environment["FFMPEG_PATH"]?.nonEmpty {
            return configured
        }
        let candidates = [
            defaultFFmpegPath,                       // Homebrew, Apple silicon
            "/usr/local/bin/ffmpeg",                 // Homebrew, Intel
            "/opt/homebrew/sbin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? defaultFFmpegPath
    }

    public static let defaultHost = "127.0.0.1"
    public static let defaultPort = 9000
    public static let allInterfacesHost = "0.0.0.0"

    /// Default ffmpeg location for Homebrew on Apple silicon.
    public static let defaultFFmpegPath = "/opt/homebrew/bin/ffmpeg"

    /// Whether a token is configured, meaning requests must authenticate.
    ///
    /// Mirrors what the middleware does, so a blank token never reports itself as
    /// authentication while silently letting every request through.
    public var requiresAuthentication: Bool {
        token?.nonEmpty != nil
    }

    /// Base URL clients should use, preferring a routable address over the
    /// `0.0.0.0` wildcard bind.
    public var displayURL: String {
        let host = self.host == Self.allInterfacesHost ? "127.0.0.1" : self.host
        return "http://\(host):\(port)"
    }

    /// Reads configuration from environment variables, falling back to defaults.
    public static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TTSServerConfiguration {
        let host = environment["HTTP_HOST"]?.nonEmpty ?? defaultHost
        let port = environment["HTTP_PORT"].flatMap(Int.init) ?? defaultPort
        let token = environment["HTTP_TOKEN"]?.nonEmpty
        let ffmpegPath = environment["FFMPEG_PATH"]?.nonEmpty ?? resolveFFmpegPath()
        return TTSServerConfiguration(host: host, port: port, token: token, ffmpegPath: ffmpegPath)
    }
}

extension String {
    /// The string itself, or nil when it is empty or only whitespace.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
