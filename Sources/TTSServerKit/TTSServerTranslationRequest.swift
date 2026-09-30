import Foundation
import Hummingbird

/// Request model for the transcription and translation endpoints
public struct TTSServerTranslationRequest: Sendable {
    public let fileURL: URL
    public let model: String
    public let responseFormat: TTSServerTranslationFormat
    public let prompt: String?
    public let temperature: Double?

    public init(
        fileURL: URL,
        model: String,
        responseFormat: TTSServerTranslationFormat = .json,
        prompt: String? = nil,
        temperature: Double? = nil
    ) {
        self.fileURL = fileURL
        self.model = model
        self.responseFormat = responseFormat
        self.prompt = prompt
        self.temperature = temperature
    }
}

/// Response format for the transcription and translation endpoints
public enum TTSServerTranslationFormat: String, Sendable, CaseIterable {
    case json
    case text

    public var contentType: String {
        switch self {
        case .json:
            return "application/json"
        case .text:
            return "text/plain"
        }
    }
}

/// Transcription / translation response model
public struct TTSServerTranslationResponse: Encodable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}
