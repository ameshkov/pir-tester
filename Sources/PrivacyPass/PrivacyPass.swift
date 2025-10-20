// Copyright 2024 Apple Inc. and the Swift Homomorphic Encryption project authors
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

import Crypto
import _CryptoExtras

typealias BackingPrivateKey = _RSA.BlindSigning.PrivateKey<SHA384>
typealias BackingPublicKey = _RSA.BlindSigning.PublicKey<SHA384>

/// Token type for Blind RSA (2048-bit).
///
/// - seealso: [RFC 9578: Privacy Pass Token
/// Types](https://www.rfc-editor.org/rfc/rfc9578#name-privacy-pass-token-types)
// swiftlint:disable:next identifier_name
public let TokenTypeBlindRSA: UInt16 = 2

// swiftlint:disable:next identifier_name
let TokenTypeBlindRSAKeySizeInBits: Int = 2048
// swiftlint:disable:next identifier_name
let TokenTypeBlindRSANK: Int = 256
// swiftlint:disable:next identifier_name
let TokenTypeBlindRSASaltLength: Int = 48
// swiftlint:disable:next identifier_name
let TokenTypeBlindRSAParams: _RSA.BlindSigning.Parameters = .RSABSSA_SHA384_PSS_Deterministic
