import Foundation

/// Generates speech using macOS say command
struct TTSServerGenerator {

    /// Generates audio from text using the say command
    /// - Parameters:
    ///   - text: The text to synthesize
    ///   - voice: Optional voice name (default system voice if nil)
    /// - Returns: URL to the generated AIFF file
    func generate(text: String, voice: String? = nil) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".aiff")

        return try await withCheckedThrowingContinuation { cont in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")

            var arguments: [String] = []
            if let voice = voice, voice != "default" {
                arguments += ["-v", voice]
            }
            arguments += ["-o", outputURL.path]
            process.arguments = arguments

            // Create a pipe for stdin to avoid encoding issues with command-line arguments
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe

            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    cont.resume(returning: outputURL)
                } else {
                    cont.resume(throwing: TTSServerError.sayCommandFailed(proc.terminationStatus))
                }
            }

            do {
                try process.run()
                // Write text to stdin with proper UTF-8 encoding
                try stdinPipe.fileHandleForWriting.write(contentsOf: text.data(using: .utf8)!)
                try stdinPipe.fileHandleForWriting.close()
            } catch {
                cont.resume(throwing: TTSServerError.processFailed(error))
            }
        }
    }
}
