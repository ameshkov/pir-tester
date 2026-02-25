import Crypto
import Foundation

/// Parsed OHTTP key configuration from RFC 9458 §3.
///
/// The binary format consists of a list of length-prefixed key
/// configurations. Each key configuration contains a key identifier,
/// KEM algorithm, public key, and supported symmetric algorithm pairs.
public struct OHTTPKeyConfiguration: Sendable {
    /// Key identifier (1 byte).
    public let keyID: UInt8
    /// KEM algorithm.
    public let kem: HPKE.KEM
    /// KEM public key bytes.
    public let publicKeyBytes: Data
    /// Supported symmetric algorithm pairs (KDF, AEAD).
    public let symmetricAlgorithms: [(kdf: HPKE.KDF, aead: HPKE.AEAD)]

    /// The first (preferred) ciphersuite.
    public var ciphersuite: HPKE.Ciphersuite {
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
    ///
    /// The outer format is a sequence of length-prefixed entries:
    /// ```
    /// KeyConfigList {
    ///   KeyConfig Length (16),
    ///   KeyConfig (..),
    ///   ...
    /// }
    /// ```
    ///
    /// Returns the first valid configuration.
    /// - Parameter data: Raw key configuration bytes.
    /// - Returns: The first successfully parsed key configuration.
    public static func parse(from data: Data) throws -> OHTTPKeyConfiguration {
        // Try parsing as a bare single key config first.
        // Many servers return the config without the outer
        // length-prefixed list wrapper.
        if let config = try? parseSingleConfig(from: data) {
            return config
        }

        // Fall back to the length-prefixed list format.
        var offset = 0

        while offset + 2 <= data.count {
            // Read 2 bytes — length of the next KeyConfig entry
            let length = Int(readUInt16(from: data, at: offset))
            offset += 2

            guard offset + length <= data.count else {
                throw OHTTPError.invalidKeyConfig(
                    reason: "Truncated key config entry"
                )
            }

            let entryData = data[offset..<(offset + length)]
            offset += length

            // Try parsing this entry; skip on failure
            if let config = try? parseSingleConfig(from: entryData) {
                return config
            }
        }

        throw OHTTPError.invalidKeyConfig(
            reason: "No valid key config found"
        )
    }

    /// Parse a single KeyConfig blob.
    ///
    /// Format:
    /// ```
    /// KeyConfig {
    ///   Key Identifier (8),
    ///   KEM ID (16),
    ///   KEM Public Key (Npk bytes),
    ///   Symmetric Algorithms Length (16),
    ///   Symmetric Algorithms (..),
    /// }
    /// ```
    private static func parseSingleConfig(
        from data: Data
    ) throws -> OHTTPKeyConfiguration {
        var offset = data.startIndex

        // 1 byte — keyID
        guard offset + 1 <= data.endIndex else {
            throw OHTTPError.invalidKeyConfig(
                reason: "Missing key identifier"
            )
        }
        let keyID = data[offset]
        offset += 1

        // 2 bytes — KEM ID
        guard offset + 2 <= data.endIndex else {
            throw OHTTPError.invalidKeyConfig(
                reason: "Missing KEM ID"
            )
        }
        let kemID = readUInt16(from: data, at: offset)
        offset += 2

        let kem: HPKE.KEM
        let publicKeySize: Int
        switch kemID {
        case 0x0020:
            kem = .Curve25519_HKDF_SHA256
            publicKeySize = 32
        case 0x0010:
            kem = .P256_HKDF_SHA256
            publicKeySize = 65
        case 0x0011:
            kem = .P384_HKDF_SHA384
            publicKeySize = 97
        case 0x0012:
            kem = .P521_HKDF_SHA512
            publicKeySize = 133
        default:
            throw OHTTPError.unsupportedKEM(kemID)
        }

        // Npk bytes — public key
        guard offset + publicKeySize <= data.endIndex else {
            throw OHTTPError.invalidKeyConfig(
                reason: "Truncated public key"
            )
        }
        let publicKeyBytes = Data(data[offset..<(offset + publicKeySize)])
        offset += publicKeySize

        // 2 bytes — symmetric algorithms length
        guard offset + 2 <= data.endIndex else {
            throw OHTTPError.invalidKeyConfig(
                reason: "Missing symmetric algorithms length"
            )
        }
        let symAlgLength = Int(readUInt16(from: data, at: offset))
        offset += 2

        guard offset + symAlgLength <= data.endIndex else {
            throw OHTTPError.invalidKeyConfig(
                reason: "Truncated symmetric algorithms"
            )
        }

        // Each pair is 4 bytes (2 for KDF + 2 for AEAD)
        guard symAlgLength % 4 == 0, symAlgLength > 0 else {
            throw OHTTPError.invalidKeyConfig(
                reason: "Invalid symmetric algorithms length"
            )
        }

        var algorithms: [(kdf: HPKE.KDF, aead: HPKE.AEAD)] = []
        let symEnd = offset + symAlgLength
        while offset + 4 <= symEnd {
            let kdfID = readUInt16(from: data, at: offset)
            offset += 2
            let aeadID = readUInt16(from: data, at: offset)
            offset += 2

            if let kdf = hpkeKDF(from: kdfID),
                let aead = hpkeAEAD(from: aeadID)
            {
                algorithms.append((kdf: kdf, aead: aead))
            }
        }

        guard !algorithms.isEmpty else {
            throw OHTTPError.noSymmetricAlgorithms
        }

        return OHTTPKeyConfiguration(
            keyID: keyID,
            kem: kem,
            publicKeyBytes: publicKeyBytes,
            symmetricAlgorithms: algorithms
        )
    }

    // MARK: - Helpers

    private static func readUInt16(
        from data: Data,
        at offset: Int
    ) -> UInt16 {
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func hpkeKDF(from id: UInt16) -> HPKE.KDF? {
        switch id {
        case 0x0001: return .HKDF_SHA256
        case 0x0002: return .HKDF_SHA384
        case 0x0003: return .HKDF_SHA512
        default: return nil
        }
    }

    private static func hpkeAEAD(from id: UInt16) -> HPKE.AEAD? {
        switch id {
        case 0x0001: return .AES_GCM_128
        case 0x0002: return .AES_GCM_256
        case 0x0003: return .chaChaPoly
        default: return nil
        }
    }
}
