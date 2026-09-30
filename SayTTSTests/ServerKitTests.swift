import Foundation
import HTTPTypes
import Hummingbird
import Logging
import NIOEmbedded
import Testing

@testable import SayTTS

@Suite("TTSServerKit Configuration")
struct TTSServerConfigurationTests {

    @Test("Defaults are loopback and port 9000")
    func testDefaults() {
        let configuration = TTSServerConfiguration.fromEnvironment(environment: [:])

        #expect(configuration.host == "127.0.0.1")
        #expect(configuration.port == 9000)
        #expect(configuration.token == nil)
        #expect(!configuration.requiresAuthentication)
    }

    @Test("Environment variables override the defaults")
    func testEnvironmentOverrides() {
        let configuration = TTSServerConfiguration.fromEnvironment(environment: [
            "HTTP_HOST": "0.0.0.0",
            "HTTP_PORT": "3000",
            "HTTP_TOKEN": "s3cret",
        ])

        #expect(configuration.host == "0.0.0.0")
        #expect(configuration.port == 3000)
        #expect(configuration.token == "s3cret")
        #expect(configuration.requiresAuthentication)
    }

    @Test("Blank or malformed environment values fall back to the defaults")
    func testBlankEnvironmentValues() {
        let configuration = TTSServerConfiguration.fromEnvironment(environment: [
            "HTTP_HOST": "   ",
            "HTTP_PORT": "not-a-number",
            "HTTP_TOKEN": "",
        ])

        #expect(configuration.host == "127.0.0.1")
        #expect(configuration.port == 9000)
        #expect(configuration.token == nil)
    }

    @Test("A whitespace-only token does not enable authentication")
    func testWhitespaceTokenIsNotAuthentication() {
        #expect(!TTSServerConfiguration(host: "127.0.0.1", port: 9000, token: "   ").requiresAuthentication)
        #expect(TTSServerConfiguration(host: "127.0.0.1", port: 9000, token: "abc").requiresAuthentication)
    }

    @Test("The wildcard bind address is displayed as loopback")
    func testDisplayURL() {
        #expect(
            TTSServerConfiguration(host: "0.0.0.0", port: 9000).displayURL == "http://127.0.0.1:9000"
        )
        #expect(
            TTSServerConfiguration(host: "192.168.1.10", port: 8080).displayURL == "http://192.168.1.10:8080"
        )
    }

    @Test("Configuration is equatable for UI diffing")
    func testEquatable() {
        #expect(
            TTSServerConfiguration(host: "127.0.0.1", port: 9000)
                == TTSServerConfiguration(host: "127.0.0.1", port: 9000)
        )
        #expect(
            TTSServerConfiguration(host: "127.0.0.1", port: 9000)
                != TTSServerConfiguration(host: "127.0.0.1", port: 9001)
        )
    }
}

@Suite("TTSServerKit Bearer Token Middleware")
struct BearerTokenMiddlewareTests {

    /// Runs the middleware over a synthetic request and returns its response.
    ///
    /// `HummingbirdTesting` is deliberately not used here: it drags in
    /// swift-nio-transport-services, which fails to link as a dynamic package
    /// product. Driving `handle` directly covers the same branches.
    private func response(
        token: String?,
        authorization: String?
    ) async throws -> Response {
        var headerFields: HTTPFields = [:]
        if let authorization {
            headerFields[.authorization] = authorization
        }

        let request = Request(
            head: .init(
                method: .get,
                scheme: "http",
                authority: "127.0.0.1:9000",
                path: "/ping",
                headerFields: headerFields
            ),
            body: .init(buffer: ByteBuffer())
        )
        let context = BasicRequestContext(
            source: ApplicationRequestContextSource(channel: EmbeddedChannel(), logger: Logger(label: "test"))
        )

        return try await BearerTokenMiddleware(token: token).handle(request, context: context) { _, _ in
            Response(status: .ok)
        }
    }

    private func status(token: String?, authorization: String?) async throws -> HTTPResponse.Status {
        try await response(token: token, authorization: authorization).status
    }

    @Test("Requests pass through when no token is configured")
    func testPassesThroughWithoutToken() async throws {
        #expect(try await status(token: nil, authorization: nil) == .ok)
        #expect(try await status(token: "", authorization: nil) == .ok)
        #expect(try await status(token: "   ", authorization: nil) == .ok)
    }

    @Test("Requests pass through with a matching token")
    func testPassesThroughWithToken() async throws {
        #expect(try await status(token: "abc", authorization: "Bearer abc") == .ok)
        // The scheme is case-insensitive per RFC 7235.
        #expect(try await status(token: "abc", authorization: "bearer abc") == .ok)
    }

    @Test("Requests without credentials are rejected")
    func testRejectsMissingToken() async throws {
        #expect(try await status(token: "abc", authorization: nil) == .unauthorized)
    }

    @Test("Requests with the wrong token are rejected")
    func testRejectsWrongToken() async throws {
        #expect(try await status(token: "abc", authorization: "Bearer wrong") == .unauthorized)
        #expect(try await status(token: "abc", authorization: "Bearer abcd") == .unauthorized)
        #expect(try await status(token: "abc", authorization: "Bearer ab") == .unauthorized)
    }

    @Test("Non-bearer schemes are rejected")
    func testRejectsOtherSchemes() async throws {
        #expect(try await status(token: "abc", authorization: "Basic abc") == .unauthorized)
        #expect(try await status(token: "abc", authorization: "abc") == .unauthorized)
    }

    @Test("A rejection advertises the bearer scheme")
    func testRejectionCarriesChallenge() async throws {
        let response = try await response(token: "abc", authorization: nil)

        #expect(response.status == .unauthorized)
        #expect(response.headers[.wwwAuthenticate] == "Bearer")
    }

    @Test("Only the exact token matches")
    func testMatching() {
        #expect(BearerTokenMiddleware.matches(provided: "abc", expected: "abc"))
        #expect(!BearerTokenMiddleware.matches(provided: "abc", expected: "abd"))
        #expect(!BearerTokenMiddleware.matches(provided: "abc", expected: "abcd"))
        #expect(!BearerTokenMiddleware.matches(provided: "", expected: "abc"))
    }
}

@Suite("TTSServerKit Multipart Parsing")
struct MultipartParsingTests {

    private func form(fields: [(name: String, value: String)], boundary: String = "X-Boundary") -> Data {
        var data = Data()
        for field in fields {
            data.append(Data("--\(boundary)\r\n".utf8))
            data.append(Data("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n".utf8))
            data.append(Data("\(field.value)\r\n".utf8))
        }
        data.append(Data("--\(boundary)--\r\n".utf8))
        return data
    }

    @Test("Form fields are parsed without trailing newlines")
    func testParsesFields() {
        let parts = parseMultipartFormData(
            data: form(fields: [("model", "ru-RU"), ("response_format", "text")]),
            boundary: "X-Boundary"
        )

        #expect(String(data: parts["model"]?.data ?? Data(), encoding: .utf8) == "ru-RU")
        #expect(String(data: parts["response_format"]?.data ?? Data(), encoding: .utf8) == "text")
    }

    @Test("Filenames are captured from the content disposition")
    func testCapturesFilename() {
        let boundary = "X-Boundary"
        var data = Data()
        data.append(Data("--\(boundary)\r\n".utf8))
        data.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"russian.wav\"\r\n".utf8))
        data.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        data.append(Data("RIFFfake".utf8))
        data.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let parts = parseMultipartFormData(data: data, boundary: boundary)

        #expect(parts["file"]?.filename == "russian.wav")
        #expect(parts["file"]?.data == Data("RIFFfake".utf8))
    }

    @Test("Binary payloads survive parsing")
    func testPreservesBinaryData() {
        let boundary = "X-Boundary"
        let payload = Data((0...255).map { UInt8($0) })
        var data = Data()
        data.append(Data("--\(boundary)\r\n".utf8))
        data.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"blob.bin\"\r\n\r\n".utf8))
        data.append(payload)
        data.append(Data("\r\n--\(boundary)--\r\n".utf8))

        #expect(parseMultipartFormData(data: data, boundary: boundary)["file"]?.data == payload)
    }

    @Test("An empty boundary yields no parts")
    func testEmptyBoundary() {
        #expect(parseMultipartFormData(data: Data("whatever".utf8), boundary: "").isEmpty)
    }
}
