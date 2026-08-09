// Copyright 2024-2025 Apple Inc. and the Swift Homomorphic Encryption project authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import HTTPTypes
import HomomorphicEncryption
import HummingbirdTesting
import NIOCore
import PrivacyPass
import PrivateInformationRetrieval
import PrivateInformationRetrievalProtobuf
import Testing
import Util

@testable import PIRServiceTesting

/// Stub test client for testing PIRClient.
/// This client throws an error if any network method is called,
/// which should not happen in these unit tests.
struct StubTestClient: TestClientProtocol {
    struct UnexpectedCallError: Error {}

    var port: Int? {
        return nil
    }

    func executeRequest(
        uri: String,
        method: HTTPRequest.Method,
        headers: HTTPFields,
        body: ByteBuffer?
    ) async throws -> HummingbirdTesting.TestResponse {
        throw UnexpectedCallError()
    }
}

@Suite("PIRClient Tests")
struct PIRClientTests {
    typealias TestPIRClient = PIRClient<MulPirClient<Bfv<UInt64>>>

    // MARK: - Configuration Tests

    @Test("Configuration initialization")
    func testConfigurationInitialization() {
        let config = Apple_SwiftHomomorphicEncryption_Api_Pir_V1_PIRConfig()
        let configId = Data([1, 2, 3, 4])

        let configuration = TestPIRClient.Configuration(
            config: config,
            configurationId: configId
        )

        #expect(configuration.configurationId == configId)
    }

    @Test("Configuration hashable")
    func testConfigurationHashable() {
        let config = Apple_SwiftHomomorphicEncryption_Api_Pir_V1_PIRConfig()
        let configId = Data([1, 2, 3, 4])

        let configuration1 = TestPIRClient.Configuration(
            config: config,
            configurationId: configId
        )
        let configuration2 = TestPIRClient.Configuration(
            config: config,
            configurationId: configId
        )

        #expect(configuration1 == configuration2)
    }

    // MARK: - StoredSecretKey Tests

    @Test("StoredSecretKey initialization with default timestamp")
    func testStoredSecretKeyDefaultTimestamp() {
        let secretKey = SerializedSecretKey(polys: [])
        let before = Date.now
        let storedKey = TestPIRClient.StoredSecretKey(secretKey: secretKey)
        let after = Date.now

        #expect(storedKey.secretKey == secretKey)
        #expect(storedKey.timestamp >= UInt64(before.timeIntervalSince1970))
        #expect(storedKey.timestamp <= UInt64(after.timeIntervalSince1970))
    }

    @Test("StoredSecretKey initialization with custom timestamp")
    func testStoredSecretKeyCustomTimestamp() {
        let secretKey = SerializedSecretKey(polys: [])
        let customDate = Date(timeIntervalSince1970: 1_234_567_890)

        let storedKey = TestPIRClient.StoredSecretKey(
            secretKey: secretKey,
            timestamp: customDate
        )

        #expect(storedKey.secretKey == secretKey)
        #expect(storedKey.timestamp == 1_234_567_890)
    }

    // MARK: - PIRClient Initialization Tests

    @Test("PIRClient default initialization")
    func testPIRClientDefaultInitialization() {
        let stubClient = StubTestClient()
        let pirClient = TestPIRClient(connection: stubClient)

        #expect(pirClient.platform == .iOS18)
        #expect(pirClient.configCache.isEmpty)
        #expect(pirClient.secretKeys.isEmpty)
        #expect(pirClient.tokens.isEmpty)
        #expect(pirClient.userToken == nil)
        #expect(pirClient.customHeaders.isEmpty)
    }

    @Test("PIRClient initialization with custom values")
    func testPIRClientCustomInitialization() {
        let stubClient = StubTestClient()
        let customUserID = UUID()
        let customPlatform = Platform.macOS15
        let configCache: [String: TestPIRClient.Configuration] = [:]
        let secretKeys: [TestPIRClient.EvaluationKeyConfigHash: TestPIRClient.StoredSecretKey] = [:]
        let userToken = "test-token"
        var customHeaders = HTTPFields()
        customHeaders.append(HTTPField(name: .userIdentifier, value: "custom-value"))

        let pirClient = TestPIRClient(
            connection: stubClient,
            userID: customUserID,
            platform: customPlatform,
            configCache: configCache,
            secretKeys: secretKeys,
            tokens: [],
            userToken: userToken,
            customHeaders: customHeaders
        )

        #expect(pirClient.userID == customUserID)
        #expect(pirClient.platform == customPlatform)
        #expect(pirClient.configCache.isEmpty)
        #expect(pirClient.secretKeys.isEmpty)
        #expect(pirClient.tokens.isEmpty)
        #expect(pirClient.userToken == userToken)
        #expect(pirClient.customHeaders == customHeaders)
    }

    // MARK: - Platform Tests

    @Test("PIRClient platform mutation")
    func testPlatformMutation() {
        let stubClient = StubTestClient()
        var pirClient = TestPIRClient(connection: stubClient, platform: .macOS15)

        #expect(pirClient.platform == .macOS15)

        pirClient.platform = .iOS18
        #expect(pirClient.platform == .iOS18)
    }

    // MARK: - UserID Tests

    @Test("PIRClient userID mutation")
    func testUserIDMutation() {
        let stubClient = StubTestClient()
        let initialUserID = UUID()
        var pirClient = TestPIRClient(connection: stubClient, userID: initialUserID)

        #expect(pirClient.userID == initialUserID)

        let newUserID = UUID()
        pirClient.userID = newUserID
        #expect(pirClient.userID == newUserID)
    }

    // MARK: - Configuration Cache Tests

    @Test("PIRClient configuration cache management")
    func testConfigCacheManagement() {
        let stubClient = StubTestClient()
        var pirClient = TestPIRClient(connection: stubClient)

        let config = Apple_SwiftHomomorphicEncryption_Api_Pir_V1_PIRConfig()
        let configId = Data([1, 2, 3, 4])
        let configuration = TestPIRClient.Configuration(
            config: config,
            configurationId: configId
        )

        // Add configuration
        pirClient.configCache["test-usecase"] = configuration
        #expect(pirClient.configCache.count == 1)
        #expect(pirClient.configCache["test-usecase"] == configuration)

        // Update configuration
        let newConfigId = Data([5, 6, 7, 8])
        let newConfiguration = TestPIRClient.Configuration(
            config: config,
            configurationId: newConfigId
        )
        pirClient.configCache["test-usecase"] = newConfiguration
        #expect(pirClient.configCache.count == 1)
        #expect(pirClient.configCache["test-usecase"] == newConfiguration)

        // Remove configuration
        pirClient.configCache.removeValue(forKey: "test-usecase")
        #expect(pirClient.configCache.isEmpty)
    }

    // MARK: - Secret Key Management Tests

    @Test("PIRClient secret key storage")
    func testSecretKeyStorage() {
        let stubClient = StubTestClient()
        var pirClient = TestPIRClient(connection: stubClient)

        let secretKey = SerializedSecretKey(polys: [])
        let storedKey = TestPIRClient.StoredSecretKey(secretKey: secretKey)
        let keyHash = Data([1, 2, 3, 4])

        // Add secret key
        pirClient.secretKeys[keyHash] = storedKey
        #expect(pirClient.secretKeys.count == 1)
        #expect(pirClient.secretKeys[keyHash]?.secretKey == secretKey)

        // Update secret key
        let newSecretKey = SerializedSecretKey(polys: [])
        let newStoredKey = TestPIRClient.StoredSecretKey(secretKey: newSecretKey)
        pirClient.secretKeys[keyHash] = newStoredKey
        #expect(pirClient.secretKeys.count == 1)
        #expect(pirClient.secretKeys[keyHash]?.secretKey == newSecretKey)

        // Remove secret key
        pirClient.secretKeys.removeValue(forKey: keyHash)
        #expect(pirClient.secretKeys.isEmpty)
    }

    // MARK: - Token Management Tests

    @Test("PIRClient token management")
    func testTokenManagement() {
        let stubClient = StubTestClient()
        var pirClient = TestPIRClient(connection: stubClient)

        // Create a test token
        let token = Token(
            tokenType: 0x0002,
            nonce: Array(repeating: 1, count: 32),
            challengeDigest: Array(repeating: 2, count: 32),
            tokenKeyId: Array(repeating: 3, count: 32),
            authenticator: Array(repeating: 4, count: 256)
        )

        // Add token
        pirClient.tokens.append(token)
        #expect(pirClient.tokens.count == 1)

        // Add multiple tokens
        pirClient.tokens.append(token)
        pirClient.tokens.append(token)
        #expect(pirClient.tokens.count == 3)

        // Remove token
        _ = pirClient.tokens.removeFirst()
        #expect(pirClient.tokens.count == 2)
    }

    // MARK: - User Token Tests

    @Test("PIRClient user token management")
    func testUserTokenManagement() {
        let stubClient = StubTestClient()
        var pirClient = TestPIRClient(connection: stubClient)

        #expect(pirClient.userToken == nil)

        pirClient.userToken = "test-user-token"
        #expect(pirClient.userToken == "test-user-token")

        pirClient.userToken = nil
        #expect(pirClient.userToken == nil)
    }

    // MARK: - Custom Headers Tests

    @Test("PIRClient custom headers management")
    func testCustomHeadersManagement() {
        let stubClient = StubTestClient()
        var pirClient = TestPIRClient(connection: stubClient)

        #expect(pirClient.customHeaders.isEmpty)

        let header = HTTPField(name: .userIdentifier, value: "test-value")
        pirClient.customHeaders.append(header)
        #expect(pirClient.customHeaders.count == 1)

        pirClient.customHeaders = HTTPFields()
        #expect(pirClient.customHeaders.isEmpty)
    }

    // MARK: - Multiple Configuration Tests

    @Test("PIRClient multiple configurations for different usecases")
    func testMultipleConfigurations() {
        let stubClient = StubTestClient()
        var pirClient = TestPIRClient(connection: stubClient)

        let config1 = Apple_SwiftHomomorphicEncryption_Api_Pir_V1_PIRConfig()
        let config2 = Apple_SwiftHomomorphicEncryption_Api_Pir_V1_PIRConfig()

        let configuration1 = TestPIRClient.Configuration(
            config: config1,
            configurationId: Data([1, 2, 3])
        )
        let configuration2 = TestPIRClient.Configuration(
            config: config2,
            configurationId: Data([4, 5, 6])
        )

        pirClient.configCache["usecase1"] = configuration1
        pirClient.configCache["usecase2"] = configuration2

        #expect(pirClient.configCache.count == 2)
        #expect(pirClient.configCache["usecase1"] == configuration1)
        #expect(pirClient.configCache["usecase2"] == configuration2)
    }

    // MARK: - Multiple Secret Keys Tests

    @Test("PIRClient multiple secret keys for different configurations")
    func testMultipleSecretKeys() {
        let stubClient = StubTestClient()
        var pirClient = TestPIRClient(connection: stubClient)

        let secretKey1 = SerializedSecretKey(polys: [])
        let secretKey2 = SerializedSecretKey(polys: [])

        let storedKey1 = TestPIRClient.StoredSecretKey(secretKey: secretKey1)
        let storedKey2 = TestPIRClient.StoredSecretKey(secretKey: secretKey2)

        let keyHash1 = Data([1, 2, 3])
        let keyHash2 = Data([4, 5, 6])

        pirClient.secretKeys[keyHash1] = storedKey1
        pirClient.secretKeys[keyHash2] = storedKey2

        #expect(pirClient.secretKeys.count == 2)
        #expect(pirClient.secretKeys[keyHash1]?.secretKey == secretKey1)
        #expect(pirClient.secretKeys[keyHash2]?.secretKey == secretKey2)
    }
}
