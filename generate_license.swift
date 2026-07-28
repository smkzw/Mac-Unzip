#!/usr/bin/env swift
// License key generator for MacUnzip Pro.
// Usage: swift generate_license.swift [CUSTOMER-NAME]
// Reads the private key from .secrets/license_private_key.txt

import CryptoKit
import Foundation

let privateKeyBase64 = try String(contentsOfFile: ".secrets/license_private_key.txt", encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)

guard let privateKeyData = Data(base64Encoded: privateKeyBase64),
      let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
else {
    print("ERROR: Could not load private key from .secrets/license_private_key.txt")
    exit(1)
}

// Generate random 4-char alphanumeric segments
let charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
func randomSegment() -> String {
    String((0..<4).map { _ in charset.randomElement()! })
}

let prefix = "MACUNZIP-\(randomSegment())-\(randomSegment())-\(randomSegment())"

guard let payloadData = prefix.data(using: .utf8),
      let signature = try? privateKey.signature(for: payloadData)
else {
    print("ERROR: Could not sign payload")
    exit(1)
}

// Encode signature as base64url (no padding)
var sigB64 = Data(signature).base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")

let licenseKey = "\(prefix)-\(sigB64)"

let customer = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Customer"
print("License key for \(customer):")
print(licenseKey)
print("")
print("Verify with: MACUNZIP format check + Ed25519 signature over '\(prefix)'")
