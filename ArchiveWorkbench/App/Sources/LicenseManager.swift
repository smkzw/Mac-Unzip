import CryptoKit
import Foundation
import Observation
import Security

/// Manages MacUnzip Pro license activation, storage, and verification.
///
/// License key format: `MACUNZIP-XXXX-XXXX-XXXX-<base64url-signature>`
/// The signature is an Ed25519 signature over the UTF-8 bytes of `MACUNZIP-XXXX-XXXX-XXXX`.
/// Verification is fully offline — the app embeds the public key.
@MainActor
@Observable
final class LicenseManager {
    static let shared = LicenseManager()

    // MARK: - Embedded Public Key (Ed25519, 32 bytes, base64-encoded)
    private static let rawPublicKeyBase64 = "9ApYASCIL8eLSQIitq48CKF955M/ndcoAzBJEULTRRQ="

    // MARK: - Keychain Constants

    private static let keychainService = "com.smkzw.MacUnzip.license"
    private static let keychainAccount = "pro-license-key"

    // MARK: - State

    /// Whether a valid Pro license is currently active.
    private(set) var isProLicensed: Bool = false

    /// The currently stored license key (nil if not activated).
    private(set) var storedKey: String?

    private init() {
        loadFromKeychain()
    }

    // MARK: - Public API

    /// Validates format and signature, then stores the license key in Keychain.
    /// Returns true if activation succeeded.
    @discardableResult
    func activateLicense(key: String) -> Bool {
        let normalized = Self.normalizeKey(key)
        guard Self.validateFormat(normalized) else { return false }
        guard Self.verifySignature(normalized) else { return false }
        guard saveToKeychain(normalized) else { return false }
        storedKey = normalized
        isProLicensed = true
        return true
    }

    /// Removes the license from Keychain and resets state.
    func deactivateLicense() {
        deleteFromKeychain()
        storedKey = nil
        isProLicensed = false
    }

    // MARK: - Key Format Validation

    /// Normalizes user input: trims whitespace, uppercases the prefix, removes extra spaces.
    static func normalizeKey(_ input: String) -> String {
        let trimmed = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        // Only uppercase the prefix segments (MACUNZIP-XXXX-XXXX-XXXX);
        // the base64url signature is case-sensitive.
        let parts = trimmed.split(separator: "-", maxSplits: 4, omittingEmptySubsequences: true)
        guard parts.count == 5 else { return trimmed.uppercased() }
        let prefix = parts[0...3].joined(separator: "-").uppercased()
        return prefix + "-" + parts[4]
    }

    /// Checks that the key matches `MACUNZIP-XXXX-XXXX-XXXX-<signature>` format.
    /// The first three segments after the prefix must be exactly 4 uppercase alphanumeric characters.
    /// The last segment is a base64url-encoded Ed25519 signature (86 or 88 chars with padding).
    static func validateFormat(_ key: String) -> Bool {
        // Split into exactly 5 segments: MACUNZIP, XXXX, XXXX, XXXX, SIGNATURE
        // maxSplits: 4 because base64url signatures may contain '-'
        let segments = key.split(separator: "-", maxSplits: 4, omittingEmptySubsequences: true).map(String.init)
        guard segments.count == 5 else { return false }
        guard segments[0] == "MACUNZIP" else { return false }

        // Segments 1-3: exactly 4 uppercase alphanumeric characters
        let alphanumeric = CharacterSet.alphanumerics
        for i in 1...3 {
            guard segments[i].count == 4,
                  segments[i].unicodeScalars.allSatisfy({ alphanumeric.contains($0) })
            else { return false }
        }

        // Segment 4 (signature): base64url characters, reasonable length for Ed25519 (64 bytes -> 86-88 chars)
        let signature = segments[4]
        guard signature.count >= 86, signature.count <= 90 else { return false }
        let base64urlChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=")
        guard signature.unicodeScalars.allSatisfy({ base64urlChars.contains($0) }) else { return false }

        return true
    }

    // MARK: - Ed25519 Signature Verification

    /// Verifies the Ed25519 signature embedded in the license key.
    /// The signed message is the UTF-8 encoding of `MACUNZIP-XXXX-XXXX-XXXX` (first 4 segments).
    static func verifySignature(_ key: String) -> Bool {
        let segments = key.split(separator: "-", maxSplits: 4, omittingEmptySubsequences: true).map(String.init)
        guard segments.count == 5 else { return false }

        // The signed payload is the first four segments joined by "-"
        let payload = segments[0...3].joined(separator: "-")
        guard let payloadData = payload.data(using: .utf8) else { return false }

        // Decode the signature (base64url -> Data)
        let signatureSegment = segments[4]
        guard let signatureData = base64urlDecode(signatureSegment) else { return false }

        // Load the embedded public key
        guard let publicKeyData = Data(base64Encoded: rawPublicKeyBase64),
              publicKeyData.count == 32,
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        else {
            return false
        }

        // Verify: signature over payload
        return publicKey.isValidSignature(signatureData, for: payloadData)
    }

    // MARK: - Base64url Helpers

    private static func base64urlDecode(_ input: String) -> Data? {
        var base64 = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Pad to multiple of 4
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    // MARK: - Keychain Operations

    private func loadFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            isProLicensed = false
            storedKey = nil
            return
        }
        // Re-validate on load (guards against tampered keychain entries)
        if Self.validateFormat(key) && Self.verifySignature(key) {
            storedKey = key
            isProLicensed = true
        } else {
            storedKey = nil
            isProLicensed = false
        }
    }

    private func saveToKeychain(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        // Delete any existing entry first
        deleteFromKeychain()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
