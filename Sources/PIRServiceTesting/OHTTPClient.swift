// swift-format-ignore-file
@preconcurrency import Crypto
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIOCore
import NIOHTTP1
import ObliviousHTTP
import ObliviousX

/// A generic OHTTP client that can fetch any URL through an
/// OHTTP gateway. It handles BHTTP serialisation, HPKE
/// encapsulation, and response decapsulation.
public struct OHTTPClient: Sendable {
    /// The parsed OHTTP key configuration.
    let keyConfig: OHTTPKeyConfiguration

    /// The gateway resource URL where encapsulated requests
    /// are sent.
    let gatewayResourceURL: URL

    /// Create a new OHTTP client.
    ///
    /// - Parameters:
    ///   - keyConfig: Parsed OHTTP key configuration.
    ///   - gatewayResourceURL: Gateway URL for encapsulated
    ///     requests.
    public init(
        keyConfig: OHTTPKeyConfiguration,
        gatewayResourceURL: URL
    ) {
        self.keyConfig = keyConfig
        self.gatewayResourceURL = gatewayResourceURL
    }

    /// Represents an HTTP response received through OHTTP.
    public struct Response: Sendable {
        /// HTTP status code.
        public let statusCode: Int
        /// Response headers.
        public let headers: [(String, String)]
        /// Response body.
        public let body: Data
    }

    /// Fetch a URL through the OHTTP gateway.
    ///
    /// - Parameters:
    ///   - url: The full target URL to fetch.
    ///   - method: HTTP method (default: GET).
    ///   - headers: Additional request headers.
    ///   - body: Optional request body.
    /// - Returns: The decapsulated HTTP response.
    public func fetch(
        url: URL,
        method: String = "GET",
        headers: [(String, String)] = [],
        body: Data? = nil
    ) async throws -> Response {
        // 1. Build the Binary HTTP request
        let binaryHTTP = serializeBinaryHTTP(
            url: url,
            method: method,
            headers: headers,
            body: body
        )

        // 2. Encapsulate with HPKE
        let ciphersuite = try keyConfig.ciphersuite
        let (encapsulated, sender) = try encapsulate(
            content: binaryHTTP,
            ciphersuite: ciphersuite
        )

        // 3. POST to gateway
        var urlRequest = URLRequest(url: gatewayResourceURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(
            "message/ohttp-req",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.httpBody = encapsulated

        let (responseData, response) =
            try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse
        else {
            throw OHTTPError.gatewayError(
                statusCode: 0,
                message: "Invalid gateway response"
            )
        }

        guard httpResponse.statusCode == 200 else {
            let message =
                String(data: responseData, encoding: .utf8)
                ?? "<\(responseData.count) bytes>"
            throw OHTTPError.gatewayError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        // 4. Decapsulate the response
        let decrypted: Data
        do {
            decrypted =
                try OHTTPEncapsulation.decapsulateResponse(
                    responsePayload: responseData,
                    mediaType: "message/bhttp response",
                    context: sender,
                    ciphersuite: ciphersuite
                )
        } catch {
            throw OHTTPError.decapsulationFailed(
                underlying: error
            )
        }

        // 5. Parse the Binary HTTP response
        return try parseBinaryHTTPResponse(decrypted)
    }

    // MARK: - Binary HTTP Serialisation

    /// Serialise an HTTP request into known-length Binary
    /// HTTP format (framing indicator 0) per RFC 9292.
    ///
    /// The ohttp-go reference gateway only accepts
    /// known-length encoding; the indeterminate-length
    /// format (framing indicator 2) produced by
    /// `BHTTPSerializer` is rejected.
    ///
    /// Takes a full URL and extracts scheme, authority
    /// (host), and path for the BHTTP encoding.
    private func serializeBinaryHTTP(
        url: URL,
        method: String,
        headers: [(String, String)],
        body: Data?
    ) -> Data {
        let host = url.host ?? ""
        let path = url.path.isEmpty ? "/" : url.path
        let uri: String
        if let query = url.query {
            uri = "\(path)?\(query)"
        } else {
            uri = path
        }

        var result = Data()

        // Framing indicator: 0 = known-length request
        appendVarint(0, to: &result)

        // Request control data
        appendVarintPrefixed(method, to: &result)
        appendVarintPrefixed("https", to: &result)
        appendVarintPrefixed(host, to: &result)
        appendVarintPrefixed(uri, to: &result)

        // Known-length header section: compute total byte
        // length of all field lines, then write length +
        // field lines.
        var headerBytes = Data()
        for (name, value) in headers {
            appendVarintPrefixed(
                name.lowercased(),
                to: &headerBytes
            )
            appendVarintPrefixed(value, to: &headerBytes)
        }
        appendVarint(headerBytes.count, to: &result)
        result.append(headerBytes)

        // Known-length content
        let content = body ?? Data()
        appendVarint(content.count, to: &result)
        result.append(content)

        // Known-length trailer section (empty)
        appendVarint(0, to: &result)

        return result
    }

    /// Append a QUIC variable-length integer (RFC 9000).
    private func appendVarint(
        _ value: Int,
        to data: inout Data
    ) {
        if value <= 63 {
            data.append(UInt8(value))
        } else if value <= 16383 {
            data.append(UInt8((value >> 8) | 0x40))
            data.append(UInt8(value & 0xFF))
        } else if value <= 1_073_741_823 {
            data.append(UInt8((value >> 24) | 0x80))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))
        } else {
            data.append(UInt8((value >> 56) | 0xC0))
            data.append(UInt8((value >> 48) & 0xFF))
            data.append(UInt8((value >> 40) & 0xFF))
            data.append(UInt8((value >> 32) & 0xFF))
            data.append(UInt8((value >> 24) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))
        }
    }

    /// Append a varint-prefixed UTF-8 string.
    private func appendVarintPrefixed(
        _ string: String,
        to data: inout Data
    ) {
        let bytes = Array(string.utf8)
        appendVarint(bytes.count, to: &data)
        data.append(contentsOf: bytes)
    }

    // MARK: - OHTTP Encapsulation

    /// Build the public key and encapsulate a Binary HTTP
    /// request using HPKE in a single step.
    ///
    /// Merging key construction and encapsulation avoids the
    /// need for `any`-typed intermediate values and force
    /// casts.
    private func encapsulate(
        content: Data,
        ciphersuite: HPKE.Ciphersuite
    ) throws -> (Data, HPKE.Sender) {
        let keyID = keyConfig.keyID
        let keyBytes = keyConfig.publicKeyBytes

        switch keyConfig.kem {
        case .Curve25519_HKDF_SHA256:
            let key = try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: keyBytes
            )
            return try OHTTPEncapsulation.encapsulateRequest(
                keyID: keyID,
                publicKey: key,
                ciphersuite: ciphersuite,
                mediaType: "message/bhttp request",
                content: content
            )
        case .P256_HKDF_SHA256:
            let key = try P256.KeyAgreement.PublicKey(
                x963Representation: keyBytes
            )
            return try OHTTPEncapsulation.encapsulateRequest(
                keyID: keyID,
                publicKey: key,
                ciphersuite: ciphersuite,
                mediaType: "message/bhttp request",
                content: content
            )
        case .P384_HKDF_SHA384:
            let key = try P384.KeyAgreement.PublicKey(
                x963Representation: keyBytes
            )
            return try OHTTPEncapsulation.encapsulateRequest(
                keyID: keyID,
                publicKey: key,
                ciphersuite: ciphersuite,
                mediaType: "message/bhttp request",
                content: content
            )
        case .P521_HKDF_SHA512:
            let key = try P521.KeyAgreement.PublicKey(
                x963Representation: keyBytes
            )
            return try OHTTPEncapsulation.encapsulateRequest(
                keyID: keyID,
                publicKey: key,
                ciphersuite: ciphersuite,
                mediaType: "message/bhttp request",
                content: content
            )
        default:
            throw OHTTPError.invalidKeyConfig(
                reason: "Unsupported KEM: \(keyConfig.kem)"
            )
        }
    }

    // MARK: - Binary HTTP Response Parsing

    /// Parse a decrypted Binary HTTP response.
    private func parseBinaryHTTPResponse(
        _ data: Data
    ) throws -> Response {
        var parser = BHTTPParser(role: .client)
        parser.append(ByteBuffer(data: data))
        parser.completeBodyReceived()

        var statusCode: UInt = 0
        var responseHeaders: [(String, String)] = []
        var bodyData = Data()

        while let message = try parser.nextMessage() {
            switch message {
            case .response(.head(let head)):
                statusCode = head.status.code
                responseHeaders = head.headers.map {
                    ($0.name, $0.value)
                }
            case .response(.body(let chunk)):
                var mutableChunk = chunk
                if let bytes = mutableChunk.readBytes(
                    length: mutableChunk.readableBytes
                ) {
                    bodyData.append(contentsOf: bytes)
                }
            case .response(.end):
                break
            default:
                throw OHTTPError.invalidBinaryHTTPResponse(
                    reason: "Unexpected message type"
                )
            }
        }

        guard statusCode > 0 else {
            throw OHTTPError.invalidBinaryHTTPResponse(
                reason: "No response head found"
            )
        }

        return Response(
            statusCode: Int(statusCode),
            headers: responseHeaders,
            body: bodyData
        )
    }
}
