import Crypto
import Foundation
import HTTPTypes
import HummingbirdTesting
import NIOCore
import NIOHTTP1
import ObliviousHTTP
import ObliviousX
import Testing

@testable import PIRServiceTesting

@Suite("OHTTP Tests")
struct OHTTPTests {
    // MARK: - Key Config Parsing Tests

    @Test("Parse valid OHTTP key configuration with X25519")
    func testParseValidKeyConfigX25519() throws {
        // Build a valid key config blob:
        // keyID(1) + kemID(2) + publicKey(32) + symAlgLen(2) + kdf(2) + aead(2)
        var entry = Data()
        // keyID
        entry.append(0x01)
        // KEM ID: X25519 = 0x0020
        entry.append(contentsOf: [0x00, 0x20])
        // 32 bytes of public key
        let publicKey = Data(repeating: 0xAB, count: 32)
        entry.append(publicKey)
        // Symmetric algorithms length: 4 bytes (1 pair)
        entry.append(contentsOf: [0x00, 0x04])
        // KDF: HKDF-SHA256 = 0x0001
        entry.append(contentsOf: [0x00, 0x01])
        // AEAD: AES-GCM-128 = 0x0001
        entry.append(contentsOf: [0x00, 0x01])

        // Wrap in outer list format: length-prefixed
        var data = Data()
        let length = UInt16(entry.count)
        data.append(UInt8(length >> 8))
        data.append(UInt8(length & 0xFF))
        data.append(entry)

        let config = try OHTTPKeyConfiguration.parse(from: data)

        #expect(config.keyID == 0x01)
        #expect(config.kem == .Curve25519_HKDF_SHA256)
        #expect(config.publicKeyBytes == publicKey)
        #expect(config.symmetricAlgorithms.count == 1)
        #expect(config.symmetricAlgorithms[0].kdf == .HKDF_SHA256)
        #expect(config.symmetricAlgorithms[0].aead == .AES_GCM_128)
    }

    @Test("Parse key config with multiple symmetric algorithms")
    func testParseKeyConfigMultipleSymAlgs() throws {
        var entry = Data()
        entry.append(0x02)
        // KEM ID: X25519
        entry.append(contentsOf: [0x00, 0x20])
        entry.append(Data(repeating: 0xCD, count: 32))
        // Symmetric algorithms length: 8 bytes (2 pairs)
        entry.append(contentsOf: [0x00, 0x08])
        // Pair 1: HKDF-SHA256 + AES-GCM-128
        entry.append(contentsOf: [0x00, 0x01, 0x00, 0x01])
        // Pair 2: HKDF-SHA256 + ChaCha20Poly1305
        entry.append(contentsOf: [0x00, 0x01, 0x00, 0x03])

        var data = Data()
        let length = UInt16(entry.count)
        data.append(UInt8(length >> 8))
        data.append(UInt8(length & 0xFF))
        data.append(entry)

        let config = try OHTTPKeyConfiguration.parse(from: data)

        #expect(config.symmetricAlgorithms.count == 2)
        #expect(config.symmetricAlgorithms[0].aead == .AES_GCM_128)
        #expect(config.symmetricAlgorithms[1].aead == .chaChaPoly)
    }

    @Test("Parse key config ciphersuite returns first algorithm")
    func testCiphersuiteReturnsFirst() throws {
        var entry = Data()
        entry.append(0x01)
        entry.append(contentsOf: [0x00, 0x20])
        entry.append(Data(repeating: 0x00, count: 32))
        // 2 pairs
        entry.append(contentsOf: [0x00, 0x08])
        entry.append(contentsOf: [0x00, 0x01, 0x00, 0x01])
        entry.append(contentsOf: [0x00, 0x01, 0x00, 0x03])

        var data = Data()
        let length = UInt16(entry.count)
        data.append(UInt8(length >> 8))
        data.append(UInt8(length & 0xFF))
        data.append(entry)

        let config = try OHTTPKeyConfiguration.parse(from: data)
        let ciphersuite = try config.ciphersuite

        #expect(ciphersuite.kem == .Curve25519_HKDF_SHA256)
        #expect(ciphersuite.kdf == .HKDF_SHA256)
        #expect(ciphersuite.aead == .AES_GCM_128)
    }

    // MARK: - Key Config Parsing Error Tests

    @Test("Parse empty data throws error")
    func testParseEmptyData() {
        #expect(throws: OHTTPError.self) {
            try OHTTPKeyConfiguration.parse(from: Data())
        }
    }

    @Test("Parse truncated key config throws error")
    func testParseTruncatedKeyConfig() {
        // Length says 100 bytes, but only 5 available
        var data = Data()
        data.append(contentsOf: [0x00, 0x64])
        data.append(contentsOf: [0x01, 0x02, 0x03, 0x04, 0x05])

        #expect(throws: OHTTPError.self) {
            try OHTTPKeyConfiguration.parse(from: data)
        }
    }

    @Test("Parse unsupported KEM throws error")
    func testParseUnsupportedKEM() {
        var entry = Data()
        entry.append(0x01)
        // Unsupported KEM ID: 0xFFFF
        entry.append(contentsOf: [0xFF, 0xFF])
        // Fill remaining with zeros
        entry.append(Data(repeating: 0x00, count: 40))

        var data = Data()
        let length = UInt16(entry.count)
        data.append(UInt8(length >> 8))
        data.append(UInt8(length & 0xFF))
        data.append(entry)

        #expect(throws: OHTTPError.self) {
            try OHTTPKeyConfiguration.parse(from: data)
        }
    }

    // MARK: - Binary HTTP Round-Trip Tests

    @Test("Binary HTTP request serialise and parse round-trip")
    func testBinaryHTTPRoundTrip() throws {
        let serializer = BHTTPSerializer()
        var buffer = ByteBuffer()

        let requestHead = HTTPRequestHead(
            version: .http1_1,
            method: .GET,
            uri: "/test",
            headers: HTTPHeaders([
                ("Host", "example.com"),
                ("Accept", "application/json"),
            ])
        )

        serializer.serialize(
            .request(.head(requestHead)),
            into: &buffer
        )
        serializer.serialize(
            .request(.end(nil)),
            into: &buffer
        )

        // Parse it back
        var parser = BHTTPParser(role: .server)
        parser.append(buffer)
        parser.completeBodyReceived()

        var foundHead = false
        var foundEnd = false
        var parsedURI = ""
        var parsedMethod = ""

        while let message = try parser.nextMessage() {
            switch message {
            case .request(.head(let head)):
                foundHead = true
                parsedURI = head.uri
                parsedMethod = head.method.rawValue
            case .request(.end):
                foundEnd = true
            default:
                break
            }
        }

        #expect(foundHead)
        #expect(foundEnd)
        #expect(parsedURI == "/test")
        #expect(parsedMethod == "GET")
    }

    @Test("Binary HTTP response serialise and parse round-trip")
    func testBinaryHTTPResponseRoundTrip() throws {
        let serializer = BHTTPSerializer()
        var buffer = ByteBuffer()

        let responseHead = HTTPResponseHead(
            version: .http1_1,
            status: .ok,
            headers: HTTPHeaders([
                ("Content-Type", "text/plain")
            ])
        )

        serializer.serialize(
            .response(.head(responseHead)),
            into: &buffer
        )

        let bodyText = "Hello, OHTTP!"
        var bodyBuffer = ByteBuffer(string: bodyText)
        serializer.serialize(
            .response(.body(.byteBuffer(bodyBuffer))),
            into: &buffer
        )
        serializer.serialize(
            .response(.end(nil)),
            into: &buffer
        )

        // Parse it back as client
        var parser = BHTTPParser(role: .client)
        parser.append(buffer)
        parser.completeBodyReceived()

        var statusCode: UInt = 0
        var bodyData = ByteBuffer()

        while let message = try parser.nextMessage() {
            switch message {
            case .response(.head(let head)):
                statusCode = head.status.code
            case .response(.body(var chunk)):
                bodyData.writeBuffer(&chunk)
            case .response(.end):
                break
            default:
                break
            }
        }

        #expect(statusCode == 200)
        #expect(String(buffer: bodyData) == bodyText)
    }

    // MARK: - OHTTP Encapsulation Round-Trip Tests

    @Test("OHTTP encapsulation and decapsulation round-trip")
    func testOHTTPEncapsulationRoundTrip() throws {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey
        let keyID: UInt8 = 0x42
        let ciphersuite = HPKE.Ciphersuite(
            kem: .Curve25519_HKDF_SHA256,
            kdf: .HKDF_SHA256,
            aead: .AES_GCM_128
        )

        let originalContent = Data("test request content".utf8)

        // Encapsulate
        let (encapsulated, sender) =
            try OHTTPEncapsulation.encapsulateRequest(
                keyID: keyID,
                publicKey: publicKey,
                ciphersuite: ciphersuite,
                mediaType: "message/bhttp request",
                content: originalContent
            )

        // Parse the request header to get info for decapsulation
        guard
            let (requestHeader, headerSize) =
                OHTTPEncapsulation.parseRequestHeader(
                    encapsulatedRequest: encapsulated
                )
        else {
            Issue.record("Failed to parse request header")
            return
        }

        #expect(requestHeader.keyID == keyID)
        #expect(requestHeader.kem == .Curve25519_HKDF_SHA256)

        // Decapsulate using RequestDecapsulator
        let message = encapsulated.dropFirst(headerSize)
        let decapsulator = OHTTPEncapsulation.RequestDecapsulator(
            requestHeader: requestHeader,
            message: Data(message)
        )
        let (decrypted, recipient) = try decapsulator.decapsulate(
            mediaType: "message/bhttp request",
            privateKey: privateKey
        )

        #expect(decrypted == originalContent)

        // Now test response encapsulation/decapsulation
        let responseContent = Data("test response content".utf8)
        let encapsulatedResponse =
            try OHTTPEncapsulation.encapsulateResponse(
                context: recipient,
                encapsulatedKey: requestHeader.encapsulatedKey,
                mediaType: "message/bhttp response",
                ciphersuite: ciphersuite,
                content: responseContent
            )

        let decryptedResponse =
            try OHTTPEncapsulation.decapsulateResponse(
                responsePayload: encapsulatedResponse,
                mediaType: "message/bhttp response",
                context: sender,
                ciphersuite: ciphersuite
            )

        #expect(decryptedResponse == responseContent)
    }

    // MARK: - End-to-End Integration Tests

    @Test("End-to-end: OHTTPClient fetches httpbin /get through OHTTP gateway")
    func testOHTTPClientEndToEnd() async throws {
        guard
            let configURL = URL(
                string: "https://httpbin.agrd.workers.dev/ohttp/config"
            )
        else {
            Issue.record("Invalid config URL")
            return
        }
        guard
            let gatewayURL = URL(
                string: "https://httpbin.agrd.workers.dev/ohttp/gateway"
            )
        else {
            Issue.record("Invalid gateway URL")
            return
        }
        guard
            let targetURL = URL(
                string: "https://httpbin.agrd.workers.dev/get"
            )
        else {
            Issue.record("Invalid target URL")
            return
        }

        // 1. Fetch OHTTP key configuration
        let (configData, _) =
            try await URLSession.shared.data(from: configURL)
        let keyConfig =
            try OHTTPKeyConfiguration.parse(from: configData)

        // 2. Create OHTTPClient and fetch
        let client = OHTTPClient(
            keyConfig: keyConfig,
            gatewayResourceURL: gatewayURL
        )
        let response = try await client.fetch(url: targetURL)

        // 3. Verify
        #expect(response.statusCode == 200)
        #expect(!response.body.isEmpty)

        let json =
            try JSONSerialization.jsonObject(
                with: response.body
            ) as? [String: Any]
        #expect(json != nil)
    }

    @Test("End-to-end: OHTTPClientTransport sends request through OHTTP gateway")
    func testOHTTPClientTransportEndToEnd() async throws {
        guard
            let configURL = URL(
                string: "https://httpbin.agrd.workers.dev/ohttp/config"
            )
        else {
            Issue.record("Invalid config URL")
            return
        }
        guard
            let gatewayURL = URL(
                string: "https://httpbin.agrd.workers.dev/ohttp/gateway"
            )
        else {
            Issue.record("Invalid gateway URL")
            return
        }

        // 1. Fetch OHTTP key configuration
        let (configData, configResponse) =
            try await URLSession.shared.data(from: configURL)
        guard
            let httpConfigResponse =
                configResponse as? HTTPURLResponse
        else {
            Issue.record("Unexpected response type")
            return
        }
        #expect(httpConfigResponse.statusCode == 200)
        #expect(!configData.isEmpty)

        let keyConfig = try OHTTPKeyConfiguration.parse(from: configData)
        #expect(keyConfig.kem == .Curve25519_HKDF_SHA256)
        #expect(!keyConfig.symmetricAlgorithms.isEmpty)

        // 2. Create the OHTTP transport
        guard
            let targetURL = URL(
                string: "https://httpbin.agrd.workers.dev"
            )
        else {
            Issue.record("Invalid target URL")
            return
        }
        let transport = OHTTPClientTransport(
            keyConfig: keyConfig,
            gatewayResourceURL: gatewayURL,
            pirServerURL: targetURL,
            privacyPassURL: targetURL
        )

        // 3. Send a GET request through the OHTTP transport
        let response = try await transport.executeRequest(
            uri: "/get",
            method: .get,
            headers: [:],
            body: nil
        )

        // 4. Verify the response
        #expect(response.status == .ok)
        let bodyData = Data(buffer: response.body)
        #expect(!bodyData.isEmpty)

        // The response should be valid JSON from httpbin
        let json =
            try JSONSerialization.jsonObject(
                with: bodyData
            ) as? [String: Any]
        #expect(json != nil)
    }
}
