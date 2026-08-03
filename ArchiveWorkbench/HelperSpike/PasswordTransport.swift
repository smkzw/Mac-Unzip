import Darwin

/// Owns one explicitly allocated byte buffer. The caller remains responsible
/// for any copies that existed before initialization or that operating-system
/// APIs make while consuming a bounded borrow.
public struct SecureBytes: ~Copyable {
    private let storage: UnsafeMutableRawPointer
    public let count: Int

    public init(_ bytes: [UInt8]) {
        count = bytes.count
        storage = .allocate(
            byteCount: max(1, bytes.count),
            alignment: MemoryLayout<UInt8>.alignment
        )
        if !bytes.isEmpty {
            bytes.withUnsafeBytes { source in
                storage.copyMemory(from: source.baseAddress!, byteCount: bytes.count)
            }
        }
    }

    public borrowing func withUnsafeBytes<Result>(
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) rethrows -> Result {
        try body(UnsafeRawBufferPointer(start: storage, count: count))
    }

    public mutating func zero() {
        let length = max(1, count)
        precondition(memset_s(storage, length, 0, length) == 0)
    }

    public var isZeroed: Bool {
        let bytes = storage.assumingMemoryBound(to: UInt8.self)
        for index in 0..<count where bytes[index] != 0 {
            return false
        }
        return true
    }

    deinit {
        let length = max(1, count)
        _ = memset_s(storage, length, 0, length)
        storage.deallocate()
    }
}
