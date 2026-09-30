import Foundation
import Hummingbird

/// Requires `Authorization: Bearer <token>` on every request when a token is configured.
///
/// Requests are served without authentication when the configured token is empty,
/// which keeps the default local-only setup friction free.
public struct BearerTokenMiddleware: RouterMiddleware {
    public typealias Context = BasicRequestContext

    private let token: String?

    public init(token: String?) {
        self.token = token?.nonEmpty
    }

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        // No token configured: serve every request.
        guard let token else {
            return try await next(request, context)
        }

        let provided = Self.bearerToken(from: request)
        guard let provided, Self.matches(provided: provided, expected: token) else {
            var response = Response(status: .unauthorized)
            response.headers[.contentType] = "text/plain"
            response.headers[.wwwAuthenticate] = "Bearer"
            response.body = .init(byteBuffer: .init(string: TTSServerError.unauthorized.errorDescription ?? "Unauthorized"))
            return response
        }

        return try await next(request, context)
    }

    /// Extracts the token from an `Authorization: Bearer <token>` header.
    static func bearerToken(from request: Request) -> String? {
        guard let header = request.headers[.authorization] else { return nil }
        let parts = header.split(separator: " ", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return nil }
        return parts[1].nonEmpty
    }

    /// Constant-time comparison to avoid leaking the token through timing.
    static func matches(provided: String, expected: String) -> Bool {
        let providedBytes = Array(provided.utf8)
        let expectedBytes = Array(expected.utf8)
        guard providedBytes.count == expectedBytes.count else { return false }

        var difference: UInt8 = 0
        for index in providedBytes.indices {
            difference |= providedBytes[index] ^ expectedBytes[index]
        }
        return difference == 0
    }
}
