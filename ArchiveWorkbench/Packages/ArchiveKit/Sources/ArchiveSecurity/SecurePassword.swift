import Darwin
import Foundation
import os.log

private let securePasswordLog = Logger(subsystem: "com.archiveworkbench.ArchiveKit", category: "SecurePassword")

/// A secure wrapper for password bytes that ensures:
/// - Memory is locked (mlock) to prevent swapping to disk
/// - Bytes are zeroized on deallocation
/// - Never appears in description/debugDescription
/// - Never stored in UserDefaults, logs, or diagnostics
/// - Conforms to Sendable for safe actor crossing
public final class SecurePassword: @unchecked Sendable {
    private let _bytes: UnsafeMutableRawBufferPointer
    private let _count: Int

    /// Creates a SecurePassword from a UTF-8 string.
    /// The input string should be discarded by the caller as soon as possible.
    public convenience init(_ password: String) {
        var utf8 = Array(password.utf8)
        defer {
            utf8.withUnsafeMutableBytes { ptr in
                if let base = ptr.baseAddress {
                    memset_s(base, ptr.count, 0, ptr.count)
                }
            }
        }
        self.init(copying: utf8)
    }

    /// Copies raw password bytes into locked storage. Caller should zero any
    /// temporary source buffer after this returns.
    public init(copying bytes: [UInt8]) {
        _count = bytes.count
        _bytes = UnsafeMutableRawBufferPointer.allocate(byteCount: max(_count, 1), alignment: 16)
        if _count > 0 {
            bytes.withUnsafeBytes { _bytes.copyMemory(from: $0) }
        }
        if mlock(_bytes.baseAddress, _bytes.count) != 0 {
            securePasswordLog.warning("mlock failed (errno \(errno)); password memory may be swappable")
        }
    }

    /// Copies from an existing secure password (for one-shot private-input delivery).
    public convenience init(copying other: SecurePassword) {
        var copy = other.withBytes { buffer -> [UInt8] in
            Array(buffer)
        }
        defer {
            copy.withUnsafeMutableBytes { ptr in
                if let base = ptr.baseAddress {
                    memset_s(base, ptr.count, 0, ptr.count)
                }
            }
        }
        self.init(copying: copy)
    }

    deinit {
        zero()
        if let base = _bytes.baseAddress {
            munlock(base, _bytes.count)
        }
        _bytes.deallocate()
    }

    /// Number of password bytes.
    public var count: Int { _count }

    /// Whether the password is empty.
    public var isEmpty: Bool { _count == 0 }

    /// True when every stored byte is currently zero.
    public var isZeroed: Bool {
        guard let base = _bytes.baseAddress else { return true }
        let typed = base.assumingMemoryBound(to: UInt8.self)
        for index in 0..<_count where typed[index] != 0 {
            return false
        }
        return true
    }

    /// Explicitly clears secret bytes in place. Safe to call more than once.
    public func zero() {
        if let base = _bytes.baseAddress {
            memset_s(base, _bytes.count, 0, _bytes.count)
        }
    }

    /// Provides temporary access to the password as a null-terminated C string.
    /// The closure receives a pointer that is valid only during the call.
    /// The caller must NOT retain the pointer beyond the closure.
    public func withCString<T>(_ body: (UnsafePointer<CChar>) throws -> T) rethrows -> T {
        let temp = UnsafeMutablePointer<CChar>.allocate(capacity: _count + 1)
        if mlock(temp, _count + 1) != 0 {
            securePasswordLog.warning("mlock failed for temp buffer (errno \(errno))")
        }
        defer {
            memset_s(temp, _count + 1, 0, _count + 1)
            munlock(temp, _count + 1)
            temp.deallocate()
        }
        if _count > 0 {
            memcpy(temp, _bytes.baseAddress!, _count)
        }
        temp[_count] = 0
        return try body(UnsafePointer(temp))
    }

    /// Provides temporary access to the raw password bytes.
    /// The buffer aliases the live secret storage (no copy is made) and is valid
    /// only during the call; do not retain or copy the pointer beyond the closure.
    public func withBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
        let view = UnsafeRawBufferPointer(start: _bytes.baseAddress, count: _count)
        return try body(view)
    }

    // MARK: - Prevent accidental leakage

    public var description: String { "SecurePassword(\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022})" }
    public var debugDescription: String { "SecurePassword(count: \(_count))" }
}

// MARK: - CustomStringConvertible / CustomDebugStringConvertible

extension SecurePassword: CustomStringConvertible, CustomDebugStringConvertible {}
