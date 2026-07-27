import Darwin
import Foundation

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
    public init(_ password: String) {
        var utf8 = Array(password.utf8)
        _count = utf8.count
        _bytes = UnsafeMutableRawBufferPointer.allocate(byteCount: max(_count, 1), alignment: 16)
        if _count > 0 {
            _bytes.copyMemory(from: UnsafeRawBufferPointer(start: utf8, count: _count))
        }
        // Lock memory to prevent swapping
        mlock(_bytes.baseAddress, _bytes.count)
        // Zeroize the temporary array
        utf8.withUnsafeMutableBytes { ptr in
            if let base = ptr.baseAddress {
                memset_s(base, ptr.count, 0, ptr.count)
            }
        }
    }

    /// Creates a SecurePassword from raw bytes.
    public init(bytes: [UInt8]) {
        _count = bytes.count
        _bytes = UnsafeMutableRawBufferPointer.allocate(byteCount: max(_count, 1), alignment: 16)
        if _count > 0 {
            _bytes.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: _count))
        }
        mlock(_bytes.baseAddress, _bytes.count)
    }

    deinit {
        // Zeroize before unlocking and freeing
        if let base = _bytes.baseAddress {
            memset_s(base, _bytes.count, 0, _bytes.count)
            munlock(base, _bytes.count)
        }
        _bytes.deallocate()
    }

    /// Number of password bytes.
    public var count: Int { _count }

    /// Whether the password is empty.
    public var isEmpty: Bool { _count == 0 }

    /// Provides temporary access to the password as a null-terminated C string.
    /// The closure receives a pointer that is valid only during the call.
    /// The caller must NOT retain the pointer beyond the closure.
    public func withCString<T>(_ body: (UnsafePointer<CChar>) throws -> T) rethrows -> T {
        // Create a temporary null-terminated buffer
        let temp = UnsafeMutablePointer<CChar>.allocate(capacity: _count + 1)
        defer {
            memset_s(temp, _count + 1, 0, _count + 1)
            temp.deallocate()
        }
        if _count > 0 {
            memcpy(temp, _bytes.baseAddress!, _count)
        }
        temp[_count] = 0
        return try body(UnsafePointer(temp))
    }

    /// Provides temporary access to the raw password bytes.
    /// The closure receives a buffer pointer that is valid only during the call.
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
