import Foundation
import Hummingbird

/// Errors surfaced by the TTS server and mapped to HTTP responses.
public enum TTSServerError: LocalizedError, Sendable {
    case invalidModel(String)
    case invalidVoice(String)
    case invalidInput(String)
    case formatNotSupported(String)
    case conversionFailed(String)
    case sayCommandFailed(Int32)
    case processFailed(any Error)
    case fileReadFailed(String)
    case fileWriteFailed(String)
    case recognitionFailed(String)
    case invalidFile(String)
    case missingFile
    case missingModel
    case unauthorized
    case startupFailed(String)
    case serverExitedUnexpectedly

    public var errorDescription: String? {
        switch self {
        case .invalidModel(let model):
            return "Invalid model: \(model). Supported model is 'tts-1'."
        case .invalidVoice(let voice):
            return "Invalid voice: \(voice)."
        case .invalidInput(let reason):
            return "Invalid input: \(reason)."
        case .formatNotSupported(let format):
            return "Format not supported: \(format)."
        case .conversionFailed(let reason):
            return "Audio conversion failed: \(reason)."
        case .sayCommandFailed(let status):
            return "Say command failed with exit code: \(status)."
        case .processFailed(let error):
            return "Process execution failed: \(error.localizedDescription)."
        case .fileReadFailed(let path):
            return "Failed to read file: \(path)."
        case .fileWriteFailed(let path):
            return "Failed to write file: \(path)."
        case .recognitionFailed(let reason):
            return "Speech recognition failed: \(reason)."
        case .invalidFile(let reason):
            return "Invalid file: \(reason)."
        case .missingFile:
            return "Missing required file parameter."
        case .missingModel:
            return "Missing required model parameter."
        case .unauthorized:
            return "Unauthorized: invalid or missing API token."
        case .startupFailed(let reason):
            return "Could not start the server: \(reason)"
        case .serverExitedUnexpectedly:
            return "The server stopped unexpectedly. The port may already be in use."
        }
    }

    /// Converts this error to an HTTP response
    public var asResponse: Response {
        let errorMessage = self.errorDescription ?? "Unknown error"

        // Determine status code based on error type
        let status: HTTPResponse.Status
        switch self {
        case .invalidModel, .invalidVoice, .invalidInput, .formatNotSupported, .missingFile, .missingModel, .invalidFile:
            status = .badRequest  // 400 - client error
        case .unauthorized:
            status = .unauthorized  // 401
        case .startupFailed, .serverExitedUnexpectedly:
            status = .serviceUnavailable  // 503
        case .conversionFailed, .sayCommandFailed, .processFailed, .fileReadFailed, .fileWriteFailed, .recognitionFailed:
            status = .internalServerError  // 500 - server error
        }

        var response = Response(status: status)
        response.headers[.contentType] = "text/plain"
        response.body = .init(byteBuffer: .init(string: errorMessage))
        return response
    }
}
