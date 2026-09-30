import Foundation
import Hummingbird

/// Builds the OpenAI-compatible HTTP router.
///
/// Shared by the standalone `TTSServer` executable and the embedded SayTTS service.
public struct TTSServerRouter: Sendable {
    private let converter: TTSServerAudioConverter
    private let generator: TTSServerGenerator = TTSServerGenerator()
    private let translator: TTSServerTranslator = TTSServerTranslator()

    public init(configuration: TTSServerConfiguration) {
        self.converter = TTSServerAudioConverter(ffmpegPath: configuration.ffmpegPath)
    }

    /// Creates a router with all TTS endpoints registered.
    public func makeRouter(token: String?) -> Router<BasicRequestContext> {
        let router = Router()
        router.middlewares.add(BearerTokenMiddleware(token: token))

        router.post("/v1/audio/speech") { request, context -> Response in
            do {
                let ttsRequest = try await request.decode(as: TTSServerRequest.self, context: context)
                try ttsRequest.validate()

                let format = ttsRequest.responseFormat ?? .mp3
                guard format.isSupported else {
                    throw TTSServerError.formatNotSupported(format.rawValue)
                }

                let aiffURL = try await self.generator.generate(
                    text: ttsRequest.input,
                    voice: ttsRequest.voice
                )

                let finalURL: URL
                if format == .aiff {
                    finalURL = aiffURL
                } else {
                    finalURL = try await self.converter.convert(inputURL: aiffURL, to: format)
                    try? FileManager.default.removeItem(at: aiffURL)
                }

                let audioData = try Data(contentsOf: finalURL)
                try? FileManager.default.removeItem(at: finalURL)

                var response = Response(status: .ok)
                response.headers[.contentType] = format.contentType
                response.headers[.contentDisposition] = "attachment; filename=speech.\(format.fileExtension)"
                response.body = .init(byteBuffer: .init(data: audioData))
                return response
            } catch let error as TTSServerError {
                return error.asResponse
            } catch {
                return TTSServerError.processFailed(error).asResponse
            }
        }

        // Transcriptions and translations share an implementation: both map to
        // on-device speech recognition, differing only in intent.
        router.post("/v1/audio/transcriptions") { request, _ -> Response in
            await self.handleRecognition(request)
        }

        router.post("/v1/audio/translations") { request, _ -> Response in
            await self.handleRecognition(request)
        }

        return router
    }

    /// Shared handler for the transcription and translation endpoints.
    private func handleRecognition(_ request: Request) async -> Response {
        do {
            guard let contentType = request.headers[.contentType], !contentType.isEmpty else {
                return TTSServerError.invalidFile("Missing content type").asResponse
            }

            var bodyBuffer = ByteBuffer()
            for try await byteBuffer in request.body {
                bodyBuffer.writeImmutableBuffer(byteBuffer)
            }
            let bodyData = Data(buffer: bodyBuffer)

            let boundary = contentType.components(separatedBy: "boundary=").last ?? ""
            let parts = parseMultipartFormData(data: bodyData, boundary: boundary)

            guard let fileData = parts["file"]?.data, let filename = parts["file"]?.filename else {
                return TTSServerError.missingFile.asResponse
            }

            guard let modelData = parts["model"]?.data,
                  let model = String(data: modelData, encoding: .utf8)?.nonEmpty else {
                return TTSServerError.missingModel.asResponse
            }

            let requestedFormat: String?
            if let formatData = parts["response_format"]?.data,
               let formatString = String(data: formatData, encoding: .utf8) {
                requestedFormat = formatString.nonEmpty
            } else {
                requestedFormat = nil
            }
            let format = requestedFormat.flatMap(TTSServerTranslationFormat.init(rawValue:)) ?? .json

            let fileExtension = URL(fileURLWithPath: filename).pathExtension.nonEmpty ?? "wav"
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            try fileData.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let transcription = try await self.translator.recognizeFile(url: tempURL, locale: model)

            switch format {
            case .json:
                let jsonData = try JSONEncoder().encode(TTSServerTranslationResponse(text: transcription))
                var response = Response(status: .ok)
                response.headers[.contentType] = TTSServerTranslationFormat.json.contentType
                response.body = .init(byteBuffer: .init(data: jsonData))
                return response
            case .text:
                var response = Response(status: .ok)
                response.headers[.contentType] = TTSServerTranslationFormat.text.contentType
                response.body = .init(byteBuffer: .init(string: transcription))
                return response
            }
        } catch let error as TTSServerError {
            return error.asResponse
        } catch {
            return TTSServerError.processFailed(error).asResponse
        }
    }
}

/// Helper struct for multipart form data parts
struct MultipartPart: Sendable {
    let data: Data
    let filename: String?
}

/// Parses multipart form data
func parseMultipartFormData(data: Data, boundary: String) -> [String: MultipartPart] {
    var parts: [String: MultipartPart] = [:]

    guard !boundary.isEmpty else {
        return parts
    }

    let boundaryData = "--\(boundary)".data(using: .utf8)!
    let headerSeparator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n

    for partData in data.split(separator: boundaryData, omittingEmptySubsequences: true) {
        // Skip the closing boundary (starts with --)
        if partData.starts(with: Data([0x2D, 0x2D])) { // "--"
            continue
        }

        if let separatorIndex = partData.range(of: headerSeparator) {
            let headerData = partData[partData.startIndex..<separatorIndex.lowerBound]
            let bodyData = partData[separatorIndex.upperBound...]
            parsePartBinary(headerData: Data(headerData), bodyData: Data(bodyData), into: &parts)
            continue
        }

        // Fall back to \n\n for non-conforming clients
        let altSeparator = Data([0x0A, 0x0A])
        guard let altIndex = partData.range(of: altSeparator) else { continue }
        let headerData = partData[partData.startIndex..<altIndex.lowerBound]
        let bodyData = partData[altIndex.upperBound...]
        parsePartBinary(headerData: Data(headerData), bodyData: Data(bodyData), into: &parts)
    }

    return parts
}

/// Helper function to parse a single multipart part from binary data
private func parsePartBinary(headerData: Data, bodyData: Data, into parts: inout [String: MultipartPart]) {
    guard let headers = String(data: headerData, encoding: .utf8) else { return }

    guard let name = firstCapture(of: "name=\"([^\"]+)\"", in: headers) else { return }
    let filename = firstCapture(of: "filename=\"([^\"]+)\"", in: headers)

    // Remove trailing \r\n or \n from body data
    var trimmedBodyData = bodyData
    if trimmedBodyData.count >= 2 {
        let lastTwoBytes = trimmedBodyData.suffix(2)
        if lastTwoBytes == Data([0x0D, 0x0A]) { // \r\n
            trimmedBodyData = Data(trimmedBodyData.dropLast(2))
        } else if trimmedBodyData.count >= 1, trimmedBodyData.suffix(1) == Data([0x0A]) { // \n
            trimmedBodyData = Data(trimmedBodyData.dropLast(1))
        }
    }

    parts[name] = MultipartPart(data: trimmedBodyData, filename: filename)
}

/// Returns the first capture group of `pattern` in `text`, if any.
private func firstCapture(of pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else {
        return nil
    }
    return String(text[range])
}
