import Darwin
import Foundation

public enum SecureMaterializationError: Error, Equatable, Sendable {
    case invalidRoot
    case fileExists
    case io(Int32)
}

public final class SecureFileWriter {
    private var descriptor: Int32

    fileprivate init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    public func write(_ data: Data) throws {
        guard descriptor >= 0 else {
            throw SecureMaterializationError.io(EBADF)
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                guard let baseAddress = bytes.baseAddress else { break }
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if result < 0 {
                    if errno == EINTR { continue }
                    throw SecureMaterializationError.io(errno)
                }
                guard result > 0 else {
                    throw SecureMaterializationError.io(EIO)
                }
                offset += result
            }
        }
    }

    fileprivate func invalidate() {
        descriptor = -1
    }
}

public final class SecureMaterializationSession {
    public let rootURL: URL
    private let rootDescriptor: Int32

    public init(rootURL: URL) throws {
        self.rootURL = rootURL
        rootDescriptor = rootURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard rootDescriptor >= 0 else {
            throw SecureMaterializationError.invalidRoot
        }
    }

    deinit {
        Darwin.close(rootDescriptor)
    }

    public func createDirectory(relativePath: String) throws -> URL {
        try ArchivePathPolicy().validate(relativePath)
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var descriptors: [Int32] = []
        defer { descriptors.reversed().forEach { Darwin.close($0) } }
        var parentFD = rootDescriptor
        for component in components {
            let mkdirResult = component.withCString { mkdirat(parentFD, $0, mode_t(0o700)) }
            if mkdirResult != 0 && errno != EEXIST {
                throw SecureMaterializationError.io(errno)
            }
            let childFD = component.withCString {
                openat(parentFD, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
            guard childFD >= 0 else {
                throw SecureMaterializationError.io(errno)
            }
            descriptors.append(childFD)
            parentFD = childFD
        }
        guard fsync(parentFD) == 0 else {
            throw SecureMaterializationError.io(errno)
        }
        return rootURL.appending(path: relativePath, directoryHint: .isDirectory)
    }

    public func write(
        relativePath: String,
        contents: (SecureFileWriter) throws -> Void
    ) throws -> URL {
        try ArchivePathPolicy().validate(relativePath)
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let leaf = components.last else {
            throw ArchiveSecurityError.emptyComponent
        }
        var descriptors: [Int32] = []
        defer { descriptors.reversed().forEach { Darwin.close($0) } }
        var parentFD = rootDescriptor
        for component in components.dropLast() {
            let mkdirResult = component.withCString { mkdirat(parentFD, $0, mode_t(0o700)) }
            if mkdirResult != 0 && errno != EEXIST {
                throw SecureMaterializationError.io(errno)
            }
            let childFD = component.withCString {
                openat(parentFD, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
            guard childFD >= 0 else {
                throw SecureMaterializationError.io(errno)
            }
            descriptors.append(childFD)
            parentFD = childFD
        }

        var leafFD = leaf.withCString {
            openat(parentFD, $0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        }
        guard leafFD >= 0 else {
            if errno == EEXIST { throw SecureMaterializationError.fileExists }
            throw SecureMaterializationError.io(errno)
        }
        var published = false
        defer {
            if leafFD >= 0 { Darwin.close(leafFD) }
            if !published { _ = leaf.withCString { unlinkat(parentFD, $0, 0) } }
        }

        let writer = SecureFileWriter(descriptor: leafFD)
        defer { writer.invalidate() }
        try contents(writer)
        guard fsync(leafFD) == 0 else { throw SecureMaterializationError.io(errno) }
        guard Darwin.close(leafFD) == 0 else {
            leafFD = -1
            throw SecureMaterializationError.io(errno)
        }
        leafFD = -1
        guard fsync(parentFD) == 0 else { throw SecureMaterializationError.io(errno) }
        published = true
        return rootURL.appending(path: relativePath)
    }
}

public struct SecureFileMaterializer: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public func write(_ data: Data, relativePath: String) throws -> URL {
        try write(relativePath: relativePath) { writer in
            try writer.write(data)
        }
    }

    public func createDirectory(relativePath: String) throws -> URL {
        try SecureMaterializationSession(rootURL: rootURL).createDirectory(relativePath: relativePath)
    }

    public func write(
        relativePath: String,
        contents: (SecureFileWriter) throws -> Void
    ) throws -> URL {
        try SecureMaterializationSession(rootURL: rootURL).write(
            relativePath: relativePath,
            contents: contents
        )
    }
}
