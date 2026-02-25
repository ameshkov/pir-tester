# Oblivious HTTP (OHTTP) Support for pir-tester

**Status**: Validated
**Implemented by**: Claude claude-sonnet-4-20250514 high

## Overview

Add optional Oblivious HTTP (OHTTP) relay support to `pir-tester` so that all
requests (both PIR and Privacy Pass) can be sent through an OHTTP gateway,
preventing the target servers from identifying the client. When OHTTP is
enabled, every HTTP request the tool makes is encapsulated using Binary HTTP +
HPKE encryption, sent to a relay/gateway, and the response is decapsulated on
the client side.

## Background

[Oblivious HTTP (RFC 9458)][ohttp-rfc] lets a client send requests to a target
server through a trusted relay so that the target cannot learn the client's
identity. The protocol works as follows:

1. The client fetches the gateway's **OHTTP key configuration** (an
   HPKE public key + ciphersuite parameters) from a well-known config resource
   URL.
2. The client encodes its HTTP request using **Binary HTTP (RFC 9292)**.
3. The Binary HTTP message is encrypted with HPKE using the gateway's public
   key, producing an **encapsulated request**.
4. The encapsulated request is POSTed to the **gateway resource URL** with
   content type `message/ohttp-req`.
5. The gateway decrypts, forwards to the target, encrypts the response, and
   returns an **encapsulated response** (`message/ohttp-res`).
6. The client decapsulates the response to obtain the original HTTP response.

[ohttp-rfc]: https://www.rfc-editor.org/rfc/rfc9458.html

## Library

Use Apple's [swift-nio-oblivious-http][sno] library. It provides two products
relevant to this feature:

- **`ObliviousHTTP`** — Binary HTTP serialisation/deserialisation (`RFC 9292`).
    - `BHTTPSerializer` — serialises `HTTPRequestHead`, body chunks, and end
      markers into a `ByteBuffer`.
    - `BHTTPParser` — deserialises a Binary HTTP message back into HTTP parts.
- **`ObliviousX`** — OHTTP encapsulation/decapsulation layer.
    - `OHTTPEncapsulation.encapsulateRequest(keyID:publicKey:ciphersuite:mediaType:content:)`
      — encrypts a Binary HTTP request, returns `(Data, HPKE.Sender)`.
    - `OHTTPEncapsulation.decapsulateResponse(responsePayload:mediaType:context:ciphersuite:)`
      — decrypts an OHTTP response using the sender context.

[sno]: https://github.com/apple/swift-nio-oblivious-http

## OHTTP Key Configuration Format

The OHTTP config resource returns a binary blob that contains one or more
length-prefixed key configurations as defined in
[RFC 9458 §3][ohttp-key-config].

The **outer list** format is a sequence of length-prefixed entries:

```text
KeyConfigList {
  KeyConfig Length (16),
  KeyConfig (..),
  KeyConfig Length (16),
  KeyConfig (..),
  ...
}
```

Each individual **KeyConfig** is encoded as:

```text
KeyConfig {
  Key Identifier (8),
  KEM ID (16),
  KEM Public Key (Npk bytes, length derived from KEM ID),
  Symmetric Algorithms Length (16),
  Symmetric Algorithms (..),
}

Symmetric Algorithms {
  KDF ID (16),
  AEAD ID (16),
}
```

The public key length (`Npk`) is not stored explicitly — it is inferred from
the KEM ID (e.g. X25519 = 32 bytes, P-256 = 65 bytes).

We need to implement a small parser for this format. The
`swift-nio-oblivious-http` library does not include a config parser, so we
will write one. The parsing logic follows the same approach as the
[ohttp-go reference implementation][ohttp-go-ref].

[ohttp-key-config]: https://www.rfc-editor.org/rfc/rfc9458.html#section-3
[ohttp-go-ref]: https://github.com/chris-wood/ohttp-go/blob/main/ohttp.go

---

## Implementation Plan

### Step 1 — Add `swift-nio-oblivious-http` dependency

**File:** `Package.swift`

Add the package dependency and wire the products into the relevant targets.

```swift
// In dependencies:
.package(
    url: "https://github.com/apple/swift-nio-oblivious-http",
    .upToNextMinor(from: "0.2.1")
),
```

Add `ObliviousHTTP` and `ObliviousX` products to the `PIRServiceTesting`
target (and to `PirTester` if needed for the config fetcher):

```swift
.product(name: "ObliviousHTTP", package: "swift-nio-oblivious-http"),
.product(name: "ObliviousX", package: "swift-nio-oblivious-http"),
```

> **Note:** `swift-nio-oblivious-http` depends on `swift-crypto` >= 4.0.0,
> while pir-tester currently depends on `swift-crypto` >= 3.10.0. This may
> require bumping the `swift-crypto` minimum version to `4.0.0` to satisfy SPM
> resolution, or the resolver may pick a compatible version automatically.
> Verify with `swift package resolve` after adding the dependency.

---

### Step 2 — Implement OHTTP key configuration parser

**New file:** `Sources/PIRServiceTesting/OHTTPKeyConfig.swift`

Create a struct that can parse the binary key configuration format from
RFC 9458 §3:

```swift
import Crypto
import Foundation

/// Parsed OHTTP key configuration from RFC 9458 §3.
struct OHTTPKeyConfiguration {
    /// Key identifier (1 byte).
    let keyID: UInt8
    /// KEM algorithm.
    let kem: HPKE.KEM
    /// KEM public key bytes.
    let publicKeyBytes: Data
    /// Supported symmetric algorithm pairs (KDF, AEAD).
    let symmetricAlgorithms: [(kdf: HPKE.KDF, aead: HPKE.AEAD)]

    /// The first (preferred) ciphersuite.
    var ciphersuite: HPKE.Ciphersuite {
        get throws {
            guard let first = symmetricAlgorithms.first else {
                throw OHTTPError.noSymmetricAlgorithms
            }
            return HPKE.Ciphersuite(
                kem: kem,
                kdf: first.kdf,
                aead: first.aead
            )
        }
    }

    /// Parse one or more key configurations from raw bytes.
    /// Returns the first valid configuration.
    static func parse(from data: Data) throws -> OHTTPKeyConfiguration
}
```

Parsing logic for `parse(from:)` — parse the **outer list**, return the first
valid config:

1. Read 2 bytes (big-endian UInt16) — length of the next `KeyConfig` entry.
2. Read that many bytes — one `KeyConfig` blob.
3. Parse the `KeyConfig` blob (see below).
4. If parsing succeeds, return the config. Otherwise, skip to the next entry
   and repeat from step 1.

Parsing logic for a single **KeyConfig** blob:

1. Read 1 byte — `keyID`.
2. Read 2 bytes (big-endian UInt16) — KEM ID, map to `HPKE.KEM`.
3. Derive `Npk` (public key size) from the KEM ID, read `Npk` bytes — public
   key.
4. Read 2 bytes — length of the symmetric algorithms section.
5. Read pairs of `(UInt16 KDF ID, UInt16 AEAD ID)` until the section is
   consumed.

---

### Step 3 — Create an OHTTP transport wrapper

**New file:** `Sources/PIRServiceTesting/OHTTPClientTransport.swift`

Create a struct that wraps any `TestClientProtocol` and transparently applies
OHTTP encapsulation/decapsulation:

```swift
/// Wraps an HTTP transport and applies OHTTP encapsulation.
///
/// When a request is executed through this transport:
/// 1. The original request is serialised into Binary HTTP.
/// 2. The Binary HTTP message is encrypted using the OHTTP gateway's
///    public key.
/// 3. The encapsulated request is POSTed to the gateway resource URL.
/// 4. The encapsulated response is decrypted and deserialised back
///    into an HTTP response.
struct OHTTPClientTransport: TestClientProtocol, Sendable {
    /// The underlying HTTP transport used to reach the gateway.
    let inner: TestClientProtocol

    /// The parsed OHTTP key configuration.
    let keyConfig: OHTTPKeyConfiguration

    /// The gateway resource URL path where encapsulated requests
    /// are sent.
    let gatewayResourcePath: String

    /// The target server's origin (scheme + host + port), used to
    /// build the Binary HTTP Host header.
    let targetOrigin: String

    var port: Int? { inner.port }

    func executeRequest(
        uri: String,
        method: HTTPRequest.Method,
        headers: HTTPFields,
        body: ByteBuffer?
    ) async throws -> TestResponse {
        // 1. Build an HTTPRequestHead for Binary HTTP serialisation
        // 2. Serialise to Binary HTTP using BHTTPSerializer
        // 3. Encapsulate with OHTTPEncapsulation.encapsulateRequest
        // 4. POST to gatewayResourcePath via inner transport with:
        //    Content-Type: message/ohttp-req
        // 5. Decapsulate the response with
        //    OHTTPEncapsulation.decapsulateResponse
        // 6. Parse Binary HTTP response using BHTTPParser
        // 7. Return TestResponse
    }
}
```

Key implementation details for `executeRequest`:

**Serialising the request to Binary HTTP:**

```swift
let serializer = BHTTPSerializer()
var buffer = ByteBuffer()

let requestHead = HTTPRequestHead(
    version: .http1_1,
    method: httpMethod,       // Map HTTPRequest.Method → NIOHTTP1.HTTPMethod
    uri: uri,
    headers: httpHeaders      // Map HTTPFields → NIOHTTP1.HTTPHeaders
)

serializer.serialize(.request(.head(requestHead)), into: &buffer)
if let body = body, body.readableBytes > 0 {
    serializer.serialize(.request(.body(.byteBuffer(body))), into: &buffer)
}
serializer.serialize(.request(.end(nil)), into: &buffer)
```

**Encapsulating:**

```swift
let ciphersuite = try keyConfig.ciphersuite
let publicKey = try ciphersuite.kem.publicKey(from: keyConfig.publicKeyBytes)
let (encapsulated, sender) = try OHTTPEncapsulation.encapsulateRequest(
    keyID: keyConfig.keyID,
    publicKey: publicKey,
    ciphersuite: ciphersuite,
    mediaType: "message/bhttp request",
    content: Data(buffer: buffer)
)
```

**Sending to the gateway:**

```swift
var requestBuffer = ByteBuffer()
requestBuffer.writeBytes(encapsulated)

let gatewayResponse = try await inner.executeRequest(
    uri: gatewayResourcePath,
    method: .post,
    headers: [
        .contentType: "message/ohttp-req"
    ],
    body: requestBuffer
)
```

**Decapsulating the response:**

```swift
let decrypted = try OHTTPEncapsulation.decapsulateResponse(
    responsePayload: Data(buffer: gatewayResponse.body),
    mediaType: "message/bhttp response",
    context: sender,
    ciphersuite: ciphersuite
)
```

**Parsing Binary HTTP response:**

```swift
var parser = BHTTPParser()
parser.append(ByteBuffer(data: decrypted))
parser.completeBodyReceived()

// Read response head, body chunks, and end from the parser
// to reconstruct a TestResponse.
```

---

### Step 4 — Add CLI arguments for OHTTP

**File:** `Sources/PirTester/main.swift`

Add two new optional arguments to the `Query` command:

```swift
@Option(
    name: .long,
    help: "URL of the OHTTP config resource (enables OHTTP when set)"
)
var ohttpConfigUrl: String?

@Option(
    name: .long,
    help: "URL of the OHTTP gateway resource"
)
var ohttpGatewayUrl: String?
```

Validation rules:

- Both arguments are optional.
- If `--ohttp-config-url` is provided, `--ohttp-gateway-url` **must** also be
  provided (and vice versa). Emit a `ValidationError` if only one is set.

---

### Step 5 — Integrate OHTTP transport into the request flow

**File:** `Sources/PirTester/main.swift`

In the `run()` method, after creating the base `HTTPClient`, conditionally
wrap it in `OHTTPClientTransport`:

```swift
// Create base HTTP client
let baseHttpClient = HTTPClient(
    pirServerURL: pirServerURL,
    privacyPassURL: privacyPassURL
)

// Optionally wrap with OHTTP
let httpClient: any TestClientProtocol
if let configUrl = ohttpConfigUrl, let gatewayUrl = ohttpGatewayUrl {
    // 1. Fetch OHTTP key config from configUrl
    let (configData, _) = try await URLSession.shared.data(
        from: URL(string: configUrl)!
    )
    let keyConfig = try OHTTPKeyConfiguration.parse(from: configData)

    // 2. Wrap with OHTTP transport
    //    The gateway URL is what inner.executeRequest will hit.
    //    We need a separate HTTPClient or adjust the existing one
    //    to route to the gateway.
    httpClient = OHTTPClientTransport(
        inner: baseHttpClient,
        keyConfig: keyConfig,
        gatewayResourcePath: gatewayUrl,
        targetOrigin: pirServerUrl
    )

    print("OHTTP enabled, gateway: \(gatewayUrl)")
} else {
    httpClient = baseHttpClient
}
```

**Important design note:** The `OHTTPClientTransport` wraps the base
`HTTPClient`, but the encapsulated request must be sent to the **gateway URL**,
not to the PIR server. The `inner` transport needs to know how to route
requests to the gateway. There are two approaches:

1. **Dedicated gateway HTTP client:** Create a separate `HTTPClient`-like
   struct that always sends to the gateway URL. The `OHTTPClientTransport`
   uses this as its `inner`.
2. **Override URL in the transport:** The `OHTTPClientTransport` constructs
   the full gateway URL itself and uses `URLSession` directly rather than
   delegating to `inner`.

Option 2 is simpler and avoids coupling with the existing `HTTPClient` routing
logic. The `OHTTPClientTransport` would use `URLSession` directly to POST to
the gateway resource URL, keeping the encapsulation self-contained.

Revised design for `OHTTPClientTransport`:

```swift
struct OHTTPClientTransport: TestClientProtocol, Sendable {
    let keyConfig: OHTTPKeyConfiguration
    let gatewayResourceURL: URL
    let targetOrigin: String

    var port: Int? { nil }

    func executeRequest(
        uri: String,
        method: HTTPRequest.Method,
        headers: HTTPFields,
        body: ByteBuffer?
    ) async throws -> TestResponse {
        // All requests (PIR and Privacy Pass) go through OHTTP:
        // 1. Serialise to Binary HTTP
        // 2. Encrypt with HPKE
        // 3. POST to gateway
        // 4. Decrypt response
        // 5. Parse Binary HTTP response
    }
}
```

All traffic (both PIR and Privacy Pass) is routed through the OHTTP gateway
when OHTTP is enabled.

---

### Step 6 — Add OHTTP error types

**File:** `Sources/PIRServiceTesting/PIRClientError.swift` (or a new
`OHTTPError.swift`)

Add error cases for OHTTP-specific failures:

```swift
enum OHTTPError: Error, CustomStringConvertible {
    /// Failed to fetch the OHTTP key configuration.
    case failedToFetchConfig(statusCode: Int, message: String)
    /// The OHTTP key configuration data is malformed.
    case invalidKeyConfig(reason: String)
    /// No symmetric algorithms found in the key configuration.
    case noSymmetricAlgorithms
    /// Unsupported KEM algorithm in the key configuration.
    case unsupportedKEM(UInt16)
    /// Failed to decapsulate the OHTTP response.
    case decapsulationFailed(underlying: Error)
    /// The gateway returned a non-200 response.
    case gatewayError(statusCode: Int, message: String)
    /// Failed to parse Binary HTTP response.
    case invalidBinaryHTTPResponse(reason: String)

    var description: String { ... }
}
```

---

### Step 7 — Add unit tests

**New file:** `Tests/PirTesterTests/OHTTPTests.swift`

The following public OHTTP gateway can be used for testing:

- **Config resource:** `https://httpbin.agrd.workers.dev/ohttp/config`
- **Gateway resource:** `https://httpbin.agrd.workers.dev/ohttp/gateway`
- **Test target URL:** `https://httpbin.agrd.workers.dev/get`

Tests to add:

1. **Key config parsing** — Test `OHTTPKeyConfiguration.parse(from:)` with
   known-good binary data (construct test vectors manually).
2. **Key config parsing — invalid data** — Verify proper errors on truncated
   or malformed input.
3. **Binary HTTP round-trip** — Serialise a request with `BHTTPSerializer`,
   parse it back with `BHTTPParser`, verify equality.
4. **OHTTP encapsulation round-trip** — Generate an HPKE key pair, encapsulate
   a request, decapsulate it with the private key, verify the content matches.
5. **OHTTPClientTransport routing** — Verify that all requests (both PIR and
   Privacy Pass) are routed through OHTTP when enabled.
6. **Integration test with real OHTTP gateway** — Fetch the key configuration
   from `https://httpbin.agrd.workers.dev/ohttp/config`, encapsulate a GET
   request to `https://httpbin.agrd.workers.dev/get`, send it through the
   gateway at `https://httpbin.agrd.workers.dev/ohttp/gateway`, decapsulate
   the response, and verify it contains a valid JSON body. This test exercises
   the full OHTTP flow end-to-end against a real relay.

---

### Step 8 — Update documentation

**File:** `README.md`

Add an OHTTP section to the README:

```markdown
## OHTTP Support

To route PIR queries through an Oblivious HTTP gateway, provide the
OHTTP config resource URL and gateway resource URL:

    PirTester query \
        --pir-server-url <pir-server-url> \
        --privacy-pass-url <privacy-pass-url> \
        --pir-usecase <pir-usecase> \
        --user-token <user-token> \
        --ohttp-config-url <ohttp-config-url> \
        --ohttp-gateway-url <ohttp-gateway-url> \
        <keyword>

When these options are set, all requests (both PIR and Privacy Pass)
are encrypted and sent through the OHTTP gateway.
```

---

## File Change Summary

| File | Action |
| ---- | ------ |
| `Package.swift` | Add `swift-nio-oblivious-http` dependency, wire products |
| `Sources/PIRServiceTesting/OHTTPKeyConfig.swift` | **New** — OHTTP key config parser |
| `Sources/PIRServiceTesting/OHTTPClientTransport.swift` | **New** — OHTTP transport wrapper |
| `Sources/PIRServiceTesting/OHTTPError.swift` | **New** — OHTTP error types |
| `Sources/PirTester/main.swift` | Add CLI args, integrate OHTTP transport |
| `Tests/PirTesterTests/OHTTPTests.swift` | **New** — unit tests |
| `README.md` | Document OHTTP usage |

## Risks and Open Questions

1. **`swift-crypto` version conflict.** The `swift-nio-oblivious-http` library
   requires `swift-crypto` >= 4.0.0, while the project currently uses >= 3.10.0.
   Need to verify compatibility with `swift-homomorphic-encryption` after
   bumping.

2. **OHTTP media type strings.** The exact media type strings passed to
   `encapsulateRequest` and `decapsulateResponse` (`"message/bhttp request"`
   vs `"message/bhttp response"`) must match what the gateway expects. These
   are defined in the OHTTP RFC and should be verified against the gateway
   implementation.

3. **HPKE public key deserialization.** The `ObliviousX` library uses
   `HPKEDiffieHellmanPublicKey` protocol from `swift-crypto`. Need to verify
   the exact API for constructing a public key from raw bytes (e.g.,
   `Curve25519.KeyAgreement.PublicKey(rawRepresentation:)` for X25519, or
   `P256.KeyAgreement.PublicKey(x963Representation:)` for P-256).

4. **`BHTTPParser` API.** The parser uses an `append()`,
   `completeBodyReceived()`, `nextMessage()` pattern. Need to handle the
   iterator correctly to reconstruct the full response (status, headers, body).

5. **Config caching.** In the current plan, the OHTTP key config is fetched
   once at startup. If the tool is extended to long-running scenarios, consider
   caching with TTL.

6. **Error propagation.** Gateway errors (e.g., 4xx/5xx from the relay) should
   be clearly distinguished from target server errors in the error output.
