import Foundation
import HTTPTypes
import NIOCore

@testable import HummingbirdTesting

/// Wraps HTTP transport with OHTTP encapsulation.
///
/// Delegates to `OHTTPClient` for the actual OHTTP/BHTTP
/// logic. This adapter resolves path-only URIs to full
/// target URLs (PIR or Privacy Pass) and converts the
/// `OHTTPClient.Response` back to `TestResponse`.
public struct OHTTPClientTransport: TestClientProtocol, Sendable {
    /// The underlying OHTTP client.
    let client: OHTTPClient

    /// The PIR server URL.
    let pirServerURL: URL

    /// The Privacy Pass server URL.
    let privacyPassURL: URL

    /// Create a new OHTTP client transport.
    ///
    /// - Parameters:
    ///   - keyConfig: Parsed OHTTP key configuration.
    ///   - gatewayResourceURL: Gateway URL for encapsulated
    ///     requests.
    ///   - pirServerURL: PIR server URL.
    ///   - privacyPassURL: Privacy Pass server URL.
    public init(
        keyConfig: OHTTPKeyConfiguration,
        gatewayResourceURL: URL,
        pirServerURL: URL,
        privacyPassURL: URL
    ) {
        self.client = OHTTPClient(
            keyConfig: keyConfig,
            gatewayResourceURL: gatewayResourceURL
        )
        self.pirServerURL = pirServerURL
        self.privacyPassURL = privacyPassURL
    }

    public var port: Int? { nil }

    public func executeRequest(
        uri: String,
        method: HTTPRequest.Method,
        headers: HTTPFields,
        body: ByteBuffer?
    ) async throws -> TestResponse {
        // Resolve the target server based on the path
        let baseURL = resolveTargetURL(for: uri)
        guard
            let fullURL = URL(
                string: uri,
                relativeTo: baseURL
            )?.absoluteURL
        else {
            throw OHTTPError.gatewayError(
                statusCode: 0,
                message: "Failed to build target URL for: "
                    + uri
            )
        }

        // Convert headers
        var headerPairs: [(String, String)] = []
        for field in headers {
            headerPairs.append(
                (field.name.rawName, field.value)
            )
        }

        // Convert body
        var bodyData: Data?
        if let body = body, body.readableBytes > 0 {
            bodyData = Data(buffer: body)
        }

        // Delegate to OHTTPClient
        let response = try await client.fetch(
            url: fullURL,
            method: method.rawValue,
            headers: headerPairs,
            body: bodyData
        )

        // Convert back to TestResponse
        return convertResponse(response)
    }

    /// Resolve the target server URL based on the request
    /// path, mirroring the routing logic in `HTTPClient`.
    private func resolveTargetURL(
        for uri: String
    ) -> URL {
        let isPrivacyPassPath =
            uri.hasPrefix("/.well-known")
            || uri.hasPrefix("/token-key-for-user-token")
            || uri.hasPrefix("/issue")

        return isPrivacyPassPath ? privacyPassURL : pirServerURL
    }

    /// Convert an `OHTTPClient.Response` to a `TestResponse`.
    private func convertResponse(
        _ response: OHTTPClient.Response
    ) -> TestResponse {
        var httpFields = HTTPFields()
        for (name, value) in response.headers {
            if let fieldName = HTTPField.Name(name) {
                httpFields.append(
                    HTTPField(name: fieldName, value: value)
                )
            }
        }

        let httpResponse = HTTPResponse(
            status: HTTPResponse.Status(
                code: response.statusCode,
                reasonPhrase: ""
            ),
            headerFields: httpFields
        )

        var bodyBuffer = ByteBuffer()
        bodyBuffer.writeBytes(response.body)

        return TestResponse(
            head: httpResponse,
            body: bodyBuffer,
            trailerHeaders: nil
        )
    }
}
