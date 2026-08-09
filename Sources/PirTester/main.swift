// swift-format-ignore-file
import ArgumentParser
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HTTPTypes
import HomomorphicEncryption
import NIOCore
import PIRServiceTesting
import PrivateInformationRetrieval

@testable import HummingbirdTesting

/// Main command-line tool for testing PIR service
@main
struct PirTester: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "PirTester",
        abstract: "A command-line tool to test a PIR service for Apple's URL filtering API",
        subcommands: [Query.self]
    )
}

/// Query subcommand that performs a full PIR lookup
struct Query: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Perform a full PIR lookup for a keyword"
    )

    @Option(
        name: .long,
        help: "URL of the PIR server"
    )
    var pirServerUrl: String

    @Option(
        name: .long,
        help: "URL of the privacy pass service"
    )
    var privacyPassUrl: String

    @Option(
        name: .long,
        help: "PIR use case identifier"
    )
    var pirUsecase: String

    @Option(
        name: .long,
        help: "User token for authentication"
    )
    var userToken: String

    @Option(
        name: .long,
        help: "Path to input file containing keywords (one per line)"
    )
    var input: String?

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

    @Argument(help: "Keyword to query")
    var keyword: String?

    func run() throws {
        // Validate that either keyword or input file is provided, but not both
        if keyword == nil && input == nil {
            throw ValidationError("Either a keyword or an input file must be provided")
        }
        if keyword != nil && input != nil {
            throw ValidationError("Cannot specify both a keyword and an input file")
        }

        // Validate OHTTP arguments: both or neither
        if (ohttpConfigUrl == nil) != (ohttpGatewayUrl == nil) {
            throw ValidationError(
                "Both --ohttp-config-url and --ohttp-gateway-url must be provided together"
            )
        }

        print("PIR Server URL: \(pirServerUrl)")
        print("Privacy Pass URL: \(privacyPassUrl)")
        print("PIR Use Case: \(pirUsecase)")
        print("User Token: \(userToken)")
        print("")

        // Validate URLs
        guard let pirServerURL = URL(string: pirServerUrl) else {
            throw ValidationError("Invalid PIR server URL: \(pirServerUrl)")
        }

        guard let privacyPassURL = URL(string: privacyPassUrl) else {
            throw ValidationError("Invalid privacy pass URL: \(privacyPassUrl)")
        }

        // Create base HTTP client
        let baseHttpClient = HTTPClient(
            pirServerURL: pirServerURL,
            privacyPassURL: privacyPassURL
        )

        // Determine keywords to query
        let keywords: [String]
        if let keyword = keyword {
            keywords = [keyword]
        } else if let inputFile = input {
            keywords = try readKeywordsFromFile(inputFile)
        } else {
            throw ValidationError("Either a keyword or an input file must be provided")
        }

        // Create PIRClient instance once and reuse it for all queries
        // This avoids repeated key rotation when processing multiple keywords
        try runQueries(
            httpClient: baseHttpClient,
            userToken: userToken,
            keywords: keywords,
            usecase: pirUsecase,
            ohttpConfigUrl: ohttpConfigUrl,
            ohttpGatewayUrl: ohttpGatewayUrl,
            pirServerURL: pirServerURL,
            privacyPassURL: privacyPassURL
        )
    }

    /// Read keywords from a file (one per line)
    private func readKeywordsFromFile(_ path: String) throws -> [String] {
        let fileURL = URL(fileURLWithPath: path)
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        let keywords =
            content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if keywords.isEmpty {
            throw ValidationError("Input file is empty or contains no valid keywords")
        }

        return keywords
    }
}

/// Run PIR queries for one or more keywords synchronously.
///
/// Creates a single PIRClient instance and reuses it for all
/// queries. When OHTTP is enabled, fetches the key config and
/// wraps the transport.
func runQueries(
    httpClient: HTTPClient,
    userToken: String,
    keywords: [String],
    usecase: String,
    ohttpConfigUrl: String? = nil,
    ohttpGatewayUrl: String? = nil,
    pirServerURL: URL? = nil,
    privacyPassURL: URL? = nil
) throws {
    // Using thread-safe container
    final class ResultContainer: @unchecked Sendable {
        var error: Error?
        var results: [(String, String?)] = []
        let semaphore = DispatchSemaphore(value: 0)
    }

    let container = ResultContainer()

    Task {
        do {
            // Optionally wrap with OHTTP transport
            let transport: any TestClientProtocol
            if let configUrl = ohttpConfigUrl,
                let gatewayUrl = ohttpGatewayUrl
            {
                guard
                    let pirURL = pirServerURL,
                    let ppURL = privacyPassURL
                else {
                    throw ValidationError(
                        "PIR and Privacy Pass URLs are required for OHTTP"
                    )
                }
                transport = try await setupOHTTPTransport(
                    configUrl: configUrl,
                    gatewayUrl: gatewayUrl,
                    pirServerURL: pirURL,
                    privacyPassURL: ppURL
                )
            } else {
                transport = httpClient
            }

            // Create PIRClient instance once - it will be reused for all queries
            var client = PIRClient<MulPirClient<Bfv<UInt32>>>(
                connection: transport,
                userToken: userToken
            )

            print("Running full PIR lookup (fetching tokens, config, keys, and querying)...\n")

            // Process each keyword one by one with the same client instance
            for (index, keyword) in keywords.enumerated() {
                if keywords.count > 1 {
                    print("[\(index + 1)/\(keywords.count)] Querying keyword: \(keyword)")
                } else {
                    print("Querying keyword: \(keyword)")
                }

                let keywordData = KeywordValuePair.Keyword(keyword.utf8)
                let queryResults = try await client.request(
                    keywords: [keywordData],
                    usecase: usecase,
                    allowKeyRotation: true
                )

                // Flatten double optional: queryResults.first returns Value??
                let result = queryResults.first.flatMap { $0 }

                let valueStr = result.flatMap { String(bytes: $0, encoding: .utf8) } ?? "nil"
                print("✓ PIR query completed successfully, value=\(valueStr)")

                container.results.append((keyword, valueStr))
                if index < keywords.count - 1 {
                    print("")
                }
            }
        } catch {
            container.error = error
        }
        container.semaphore.signal()
    }

    container.semaphore.wait()

    if let error = container.error {
        throw error
    }

    // Print results
    print("")
    for (keyword, result) in container.results {
        if let result = result {
            print("Result for '\(keyword)': \(result)")
        } else {
            print("Result for '\(keyword)': No value found")
        }
    }

    print("\n✓ Full PIR lookup completed successfully")
}

/// HTTP client that implements TestClientProtocol for real HTTP requests
struct HTTPClient: TestClientProtocol, Sendable {
    let pirServerURL: URL
    let privacyPassURL: URL

    var port: Int? {
        return nil
    }

    func executeRequest(
        uri: String,
        method: HTTPRequest.Method,
        headers: HTTPFields,
        body: ByteBuffer?
    ) async throws -> HummingbirdTesting.TestResponse {
        // Determine which server to use based on the path
        let baseURL: URL
        let isPrivacyPassPath =
            uri.starts(with: "/.well-known")
            || uri.starts(with: "/token-key-for-user-token")
            || uri.starts(with: "/issue")

        if isPrivacyPassPath {
            baseURL = privacyPassURL
        } else {
            baseURL = pirServerURL
        }

        guard let url = URL(string: uri, relativeTo: baseURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        // Set headers
        for header in headers {
            request.setValue(header.value, forHTTPHeaderField: header.name.rawName)
        }

        // Set body if present
        if let body = body {
            request.httpBody = Data(buffer: body)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue(
                    "application/x-protobuf",
                    forHTTPHeaderField: "Content-Type"
                )
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let status = HTTPResponse.Status(code: httpResponse.statusCode)
        var buffer = ByteBuffer()
        buffer.writeBytes(data)

        let httpResponseHead = HTTPResponse(
            status: status,
            headerFields: [:]
        )
        return HummingbirdTesting.TestResponse(
            head: httpResponseHead,
            body: buffer,
            trailerHeaders: nil
        )
    }
}

/// Fetch the OHTTP key configuration and create an
/// `OHTTPClientTransport`.
func setupOHTTPTransport(
    configUrl: String,
    gatewayUrl: String,
    pirServerURL: URL,
    privacyPassURL: URL
) async throws -> OHTTPClientTransport {
    guard let configURL = URL(string: configUrl) else {
        throw ValidationError(
            "Invalid OHTTP config URL: \(configUrl)"
        )
    }
    guard let gatewayURL = URL(string: gatewayUrl) else {
        throw ValidationError(
            "Invalid OHTTP gateway URL: \(gatewayUrl)"
        )
    }

    print("Fetching OHTTP key configuration from \(configUrl)...")
    let (configData, _) = try await URLSession.shared.data(
        from: configURL
    )
    let keyConfig = try OHTTPKeyConfiguration.parse(from: configData)
    print("OHTTP enabled, gateway: \(gatewayUrl)")

    return OHTTPClientTransport(
        keyConfig: keyConfig,
        gatewayResourceURL: gatewayURL,
        pirServerURL: pirServerURL,
        privacyPassURL: privacyPassURL
    )
}

extension HTTPResponse.Status {
    init(code: Int) {
        self.init(code: code, reasonPhrase: "")
    }
}
