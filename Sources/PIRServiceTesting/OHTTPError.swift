import Foundation

/// Errors specific to OHTTP operations.
public enum OHTTPError: Error, CustomStringConvertible {
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

    public var description: String {
        switch self {
        case .invalidKeyConfig(let reason):
            return "Invalid OHTTP key config: \(reason)"
        case .noSymmetricAlgorithms:
            return "No symmetric algorithms in OHTTP key config"
        case .unsupportedKEM(let kemID):
            return "Unsupported KEM algorithm: 0x\(String(kemID, radix: 16))"
        case .decapsulationFailed(let underlying):
            return "OHTTP decapsulation failed: \(underlying)"
        case let .gatewayError(statusCode, message):
            return "OHTTP gateway error \(statusCode): \(message)"
        case .invalidBinaryHTTPResponse(let reason):
            return "Invalid Binary HTTP response: \(reason)"
        }
    }
}
