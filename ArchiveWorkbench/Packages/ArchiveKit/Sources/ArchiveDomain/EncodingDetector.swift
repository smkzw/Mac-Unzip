import Foundation

/// Confidence level for an encoding detection result.
public enum EncodingConfidence: Int, Comparable, Sendable {
    /// UTF-8 flag (bit 11) was set in the ZIP entry — definitive per spec.
    case definitive = 3
    /// Valid multi-byte sequence detected for a specific CJK encoding.
    case high = 2
    /// Fallback encoding (CP437) — no multi-byte patterns matched.
    case low = 1

    public static func < (lhs: EncodingConfidence, rhs: EncodingConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Result of encoding detection for a single entry name.
public struct EncodingDetectionResult: Equatable, Sendable {
    public let encoding: String.Encoding
    public let confidence: EncodingConfidence
    public let decodedName: String

    public init(encoding: String.Encoding, confidence: EncodingConfidence, decodedName: String) {
        self.encoding = encoding
        self.confidence = confidence
        self.decodedName = decodedName
    }
}

/// User-selectable legacy encoding options matching the Settings UI:
/// "Legacy encoding detection: 自动/UTF-8/GBK/Shift-JIS"
public enum LegacyEncodingPreference: String, CaseIterable, Sendable {
    case automatic = "automatic"
    case utf8 = "utf8"
    case gbk = "gbk"
    case shiftJIS = "shiftjis"
    case eucKR = "euckr"
    case cp437 = "cp437"

    /// The `String.Encoding` corresponding to this preference, or nil for automatic.
    public var stringEncoding: String.Encoding? {
        switch self {
        case .automatic: return nil
        case .utf8: return .utf8
        case .gbk: return LegacyEncodingPreference.gbkEncoding
        case .shiftJIS: return LegacyEncodingPreference.shiftJISEncoding
        case .eucKR: return LegacyEncodingPreference.eucKREncoding
        case .cp437: return LegacyEncodingPreference.cp437Encoding
        }
    }

    // MARK: - Encoding constants

    /// GBK (Windows code page 936, superset of GB2312).
    public static let gbkEncoding: String.Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    /// Shift-JIS (Windows code page 932).
    public static let shiftJISEncoding: String.Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)
        )
    )

    /// EUC-KR (Windows code page 949, superset including Unified Hangul).
    public static let eucKREncoding: String.Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
        )
    )

    /// CP437 — the original ZIP specification default encoding.
    public static let cp437Encoding: String.Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0400))
    )
}

/// Detects the encoding of legacy (non-UTF-8-flagged) ZIP entry names using
/// byte-pattern heuristics for common CJK encodings.
///
/// Detection strategy:
/// 1. If the UTF-8 flag (bit 11) is set → UTF-8, definitive.
/// 2. Try strict UTF-8 decode → if valid and contains multi-byte, high confidence.
/// 3. Check for GBK byte patterns (common for Chinese Windows ZIPs).
/// 4. Check for Shift-JIS byte patterns (Japanese).
/// 5. Check for EUC-KR byte patterns (Korean).
/// 6. Fallback: CP437 (original ZIP spec), low confidence.
public struct EncodingDetector: Sendable {

    public init() {}

    /// Detects encoding for a single entry's raw name bytes.
    ///
    /// - Parameters:
    ///   - rawBytes: The raw filename bytes from the ZIP central directory.
    ///   - usesUTF8Flag: Whether the UTF-8 flag (general purpose bit 11) is set.
    ///   - override: An optional user-selected encoding override. When non-nil
    ///     and not `.automatic`, this encoding is used unconditionally.
    /// - Returns: The detection result with decoded name and confidence.
    public func detect(
        rawBytes: [UInt8],
        usesUTF8Flag: Bool,
        override: LegacyEncodingPreference = .automatic
    ) -> EncodingDetectionResult {
        // 1. User override takes precedence (explicit choice).
        if let forcedEncoding = override.stringEncoding {
            let decoded = decode(bytes: rawBytes, encoding: forcedEncoding)
            return EncodingDetectionResult(
                encoding: forcedEncoding,
                confidence: .definitive,
                decodedName: decoded
            )
        }

        // 2. UTF-8 flag is definitive per ZIP spec (APPNOTE 6.3.3).
        if usesUTF8Flag {
            let decoded = decode(bytes: rawBytes, encoding: .utf8)
            return EncodingDetectionResult(
                encoding: .utf8,
                confidence: .definitive,
                decodedName: decoded
            )
        }

        // 3. Try strict UTF-8 decode — if the bytes form valid UTF-8 with
        //    multi-byte sequences, it's very likely actually UTF-8 even without
        //    the flag (common with modern tools that forget to set bit 11).
        if let utf8String = strictUTF8Decode(rawBytes), hasMultiByteUTF8(rawBytes) {
            return EncodingDetectionResult(
                encoding: .utf8,
                confidence: .high,
                decodedName: utf8String
            )
        }

        // 4. Pure ASCII — unambiguous, any encoding will produce the same result.
        if rawBytes.allSatisfy({ $0 < 0x80 }) {
            let decoded = String(bytes: rawBytes, encoding: .ascii) ?? ""
            return EncodingDetectionResult(
                encoding: .utf8,
                confidence: .definitive,
                decodedName: decoded
            )
        }

        // 5. Heuristic CJK detection on high-byte sequences.
        let gbkScore = scoreGBK(rawBytes)
        let sjisScore = scoreShiftJIS(rawBytes)
        let eucKrScore = scoreEUCKR(rawBytes)

        let bestScore = max(gbkScore, sjisScore, eucKrScore)
        if bestScore > 0 {
            let encoding: String.Encoding
            if gbkScore == bestScore {
                encoding = LegacyEncodingPreference.gbkEncoding
            } else if sjisScore == bestScore {
                encoding = LegacyEncodingPreference.shiftJISEncoding
            } else {
                encoding = LegacyEncodingPreference.eucKREncoding
            }
            let decoded = decode(bytes: rawBytes, encoding: encoding)
            return EncodingDetectionResult(
                encoding: encoding,
                confidence: .high,
                decodedName: decoded
            )
        }

        // 6. Fallback: CP437 (original ZIP spec default).
        let decoded = decode(bytes: rawBytes, encoding: LegacyEncodingPreference.cp437Encoding)
        return EncodingDetectionResult(
            encoding: LegacyEncodingPreference.cp437Encoding,
            confidence: .low,
            decodedName: decoded
        )
    }

    /// Re-decodes a set of raw name bytes with an explicit encoding override.
    /// Used when the user changes the per-archive encoding preference.
    public func decodeWithOverride(
        rawBytes: [UInt8],
        override: LegacyEncodingPreference
    ) -> String {
        guard let encoding = override.stringEncoding else {
            return detect(rawBytes: rawBytes, usesUTF8Flag: false).decodedName
        }
        return decode(bytes: rawBytes, encoding: encoding)
    }

    // MARK: - Private helpers

    private func decode(bytes: [UInt8], encoding: String.Encoding) -> String {
        if let result = String(bytes: bytes, encoding: encoding) {
            return result
        }
        // If the chosen encoding fails, fall back to lossy UTF-8 then CP437.
        if let utf8 = String(bytes: bytes, encoding: .utf8) {
            return utf8
        }
        if let cp437 = String(bytes: bytes, encoding: LegacyEncodingPreference.cp437Encoding) {
            return cp437
        }
        // Last resort: interpret each byte as a Unicode scalar (Latin-1 style).
        return bytes.map { String(UnicodeScalar($0)) }.joined()
    }

    /// Strict UTF-8 validation: returns nil if any byte sequence is invalid.
    private func strictUTF8Decode(_ bytes: [UInt8]) -> String? {
        var iterator = bytes.makeIterator()
        var scalars: [Unicode.Scalar] = []
        var decoder = UTF8()
        while true {
            switch decoder.decode(&iterator) {
            case .scalarValue(let scalar):
                scalars.append(scalar)
            case .emptyInput:
                return String(String.UnicodeScalarView(scalars))
            case .error:
                return nil
            }
        }
    }

    /// Returns true if the byte array contains any bytes >= 0x80.
    private func hasMultiByteUTF8(_ bytes: [UInt8]) -> Bool {
        bytes.contains { $0 >= 0x80 }
    }

    // MARK: - GBK scoring

    /// GBK: lead byte 0x81–0xFE, trail byte 0x40–0xFE (excluding 0x7F).
    /// Common Chinese characters have lead bytes 0xB0–0xF7 (GB2312 level 1+2).
    private func scoreGBK(_ bytes: [UInt8]) -> Int {
        var score = 0
        var i = 0
        var validPairs = 0
        var invalidSequences = 0
        while i < bytes.count {
            let b = bytes[i]
            if b >= 0x81 && b <= 0xFE {
                guard i + 1 < bytes.count else { invalidSequences += 1; break }
                let trail = bytes[i + 1]
                if trail >= 0x40 && trail <= 0xFE && trail != 0x7F {
                    validPairs += 1
                    // Bonus for common GB2312 range (Chinese characters).
                    if b >= 0xB0 && b <= 0xF7 && trail >= 0xA1 && trail <= 0xFE {
                        score += 2
                    } else {
                        score += 1
                    }
                    i += 2
                } else {
                    invalidSequences += 1
                    i += 1
                }
            } else {
                i += 1
            }
        }
        // Penalize if we found invalid sequences or no valid pairs.
        if invalidSequences > 0 || validPairs == 0 { return 0 }
        return score
    }

    // MARK: - Shift-JIS scoring

    /// Shift-JIS: lead byte 0x81–0x9F or 0xE0–0xEF, trail byte 0x40–0xFC (excluding 0x7F).
    /// Half-width katakana: 0xA1–0xDF (single byte).
    private func scoreShiftJIS(_ bytes: [UInt8]) -> Int {
        var score = 0
        var i = 0
        var validPairs = 0
        var invalidSequences = 0
        while i < bytes.count {
            let b = bytes[i]
            if (b >= 0x81 && b <= 0x9F) || (b >= 0xE0 && b <= 0xEF) {
                guard i + 1 < bytes.count else { invalidSequences += 1; break }
                let trail = bytes[i + 1]
                if trail >= 0x40 && trail <= 0xFC && trail != 0x7F {
                    validPairs += 1
                    // Bonus for common JIS X 0208 range.
                    if b >= 0x82 && b <= 0x84 {
                        score += 2 // Hiragana/Katakana region
                    } else if b >= 0x88 && b <= 0x9F {
                        score += 2 // Common kanji
                    } else {
                        score += 1
                    }
                    i += 2
                } else {
                    invalidSequences += 1
                    i += 1
                }
            } else if b >= 0xA1 && b <= 0xDF {
                // Half-width katakana — valid but less distinctive.
                score += 1
                validPairs += 1
                i += 1
            } else {
                i += 1
            }
        }
        if invalidSequences > 0 || validPairs == 0 { return 0 }
        return score
    }

    // MARK: - EUC-KR scoring

    /// EUC-KR: lead byte 0xA1–0xFE, trail byte 0xA1–0xFE.
    /// Korean Hangul syllables are in 0xB0–0xC8 lead range.
    private func scoreEUCKR(_ bytes: [UInt8]) -> Int {
        var score = 0
        var i = 0
        var validPairs = 0
        var invalidSequences = 0
        while i < bytes.count {
            let b = bytes[i]
            if b >= 0xA1 && b <= 0xFE {
                guard i + 1 < bytes.count else { invalidSequences += 1; break }
                let trail = bytes[i + 1]
                if trail >= 0xA1 && trail <= 0xFE {
                    validPairs += 1
                    // Bonus for Hangul syllable range.
                    if b >= 0xB0 && b <= 0xC8 {
                        score += 2
                    } else {
                        score += 1
                    }
                    i += 2
                } else {
                    invalidSequences += 1
                    i += 1
                }
            } else {
                i += 1
            }
        }
        if invalidSequences > 0 || validPairs == 0 { return 0 }
        return score
    }
}
