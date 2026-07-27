import CMinizipBridge
import Foundation
import XCTest

final class CMinizipBridgeTests: XCTestCase {
    func testPinnedEngineVersion() {
        XCTAssertEqual(String(cString: awb_mz_version()), "4.2.1")
    }

    func testClosedEntryCannotBeReopenedWithoutNavigation() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CMinizipBridgeTests-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("content".utf8).write(to: root.appending(path: "file.txt"))
        let archiveURL = root.appending(path: "fixture.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", archiveURL.path, "file.txt"]
        process.currentDirectoryURL = root
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        var reader: OpaquePointer?
        let openStatus = archiveURL.withUnsafeFileSystemRepresentation { path in
            awb_mz_reader_open(path, &reader)
        }
        XCTAssertEqual(openStatus, AWB_MZ_OK)
        defer { awb_mz_reader_close(&reader) }
        var info = awb_mz_entry_info()
        XCTAssertEqual(awb_mz_reader_first(reader, &info), AWB_MZ_OK)
        XCTAssertEqual(awb_mz_reader_open_current(reader), AWB_MZ_OK)
        var buffer = [UInt8](repeating: 0, count: 32)
        while buffer.withUnsafeMutableBufferPointer({
            awb_mz_reader_read_current(reader, $0.baseAddress, Int32($0.count))
        }) > 0 {}
        XCTAssertEqual(awb_mz_reader_close_current(reader), AWB_MZ_OK)

        XCTAssertEqual(awb_mz_reader_open_current(reader), AWB_MZ_INVALID_ARGUMENT)
    }

    func testWriterStreamsOneUTF8EntryAcrossMultipleChunks() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CMinizipBridgeWriterTests-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = root.appending(path: "fixture.zip")
        let first = Data("分块".utf8)
        let second = Data("写入".utf8)

        var writer: OpaquePointer?
        XCTAssertEqual(archiveURL.withUnsafeFileSystemRepresentation {
            awb_mz_writer_open($0, &writer)
        }, AWB_MZ_OK)
        XCTAssertEqual("资料/说明.txt".withCString {
            awb_mz_writer_open_entry(writer, $0, UInt64(first.count + second.count), 0)
        }, AWB_MZ_OK)
        XCTAssertEqual(first.withUnsafeBytes {
            awb_mz_writer_write_entry(writer, $0.bindMemory(to: UInt8.self).baseAddress, Int32($0.count))
        }, Int32(first.count))
        XCTAssertEqual(second.withUnsafeBytes {
            awb_mz_writer_write_entry(writer, $0.bindMemory(to: UInt8.self).baseAddress, Int32($0.count))
        }, Int32(second.count))
        XCTAssertEqual(awb_mz_writer_close_entry(writer), AWB_MZ_OK)
        XCTAssertEqual(awb_mz_writer_close(&writer), AWB_MZ_OK)

        var reader: OpaquePointer?
        XCTAssertEqual(archiveURL.withUnsafeFileSystemRepresentation {
            awb_mz_reader_open($0, &reader)
        }, AWB_MZ_OK)
        defer { awb_mz_reader_close(&reader) }
        var info = awb_mz_entry_info()
        XCTAssertEqual(awb_mz_reader_first(reader, &info), AWB_MZ_OK)
        XCTAssertEqual(info.uses_utf8_file_name, 1)
        XCTAssertEqual(info.uncompressed_size, UInt64(first.count + second.count))
        XCTAssertEqual(awb_mz_reader_open_current(reader), AWB_MZ_OK)
        var bytes = [UInt8](repeating: 0, count: first.count + second.count)
        let count = bytes.withUnsafeMutableBufferPointer {
            awb_mz_reader_read_current(reader, $0.baseAddress, Int32($0.count))
        }
        XCTAssertEqual(count, Int32(bytes.count))
        XCTAssertEqual(Data(bytes), first + second)
        XCTAssertEqual(awb_mz_reader_close_current(reader), AWB_MZ_OK)
    }

    // MARK: - Performance: O(1) goto via central directory index

    func testGotoPerformanceWith10kEntries() throws {
        let entryCount = 10_000
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CMinizipBridgePerfTests-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = root.appending(path: "large.zip")

        // Create a ZIP with 10,000 entries using the writer bridge
        var writer: OpaquePointer?
        XCTAssertEqual(archiveURL.withUnsafeFileSystemRepresentation {
            awb_mz_writer_open($0, &writer)
        }, AWB_MZ_OK)
        let payload = Data("hello".utf8)
        for i in 0..<entryCount {
            let name = "dir/file_\(String(format: "%05d", i)).txt"
            XCTAssertEqual(name.withCString {
                awb_mz_writer_open_entry(writer, $0, UInt64(payload.count), 0)
            }, AWB_MZ_OK)
            XCTAssertEqual(payload.withUnsafeBytes {
                awb_mz_writer_write_entry(writer, $0.bindMemory(to: UInt8.self).baseAddress, Int32($0.count))
            }, Int32(payload.count))
            XCTAssertEqual(awb_mz_writer_close_entry(writer), AWB_MZ_OK)
        }
        XCTAssertEqual(awb_mz_writer_close(&writer), AWB_MZ_OK)

        // Open for reading
        var reader: OpaquePointer?
        XCTAssertEqual(archiveURL.withUnsafeFileSystemRepresentation {
            awb_mz_reader_open($0, &reader)
        }, AWB_MZ_OK)
        defer { awb_mz_reader_close(&reader) }

        // Measure full listing (sequential scan)
        let listStart = CFAbsoluteTimeGetCurrent()
        var info = awb_mz_entry_info()
        XCTAssertEqual(awb_mz_reader_first(reader, &info), AWB_MZ_OK)
        var count: UInt64 = 1
        while awb_mz_reader_next(reader, &info) == AWB_MZ_OK {
            count += 1
        }
        let listElapsed = CFAbsoluteTimeGetCurrent() - listStart
        XCTAssertEqual(count, UInt64(entryCount))
        XCTAssertLessThan(listElapsed, 2.0, "Listing \(entryCount) entries took \(listElapsed)s (limit 2s)")

        // Measure O(1) seek to last entry (index is built on first goto call)
        let seekStart = CFAbsoluteTimeGetCurrent()
        var seekInfo = awb_mz_entry_info()
        let seekResult = awb_mz_reader_goto(reader, UInt64(entryCount - 1), &seekInfo)
        let seekElapsed = CFAbsoluteTimeGetCurrent() - seekStart
        XCTAssertEqual(seekResult, AWB_MZ_OK)
        // Verify we landed on the correct entry
        let expectedName = "dir/file_\(String(format: "%05d", entryCount - 1)).txt"
        let actualName = String(
            bytes: UnsafeBufferPointer(start: seekInfo.name_bytes, count: Int(seekInfo.name_size)),
            encoding: .utf8
        )
        XCTAssertEqual(actualName, expectedName)
        XCTAssertLessThan(seekElapsed, 0.1, "Seek to entry #\(entryCount - 1) took \(seekElapsed)s (limit 100ms)")

        // Second seek should be even faster (index already built)
        let seek2Start = CFAbsoluteTimeGetCurrent()
        var seek2Info = awb_mz_entry_info()
        XCTAssertEqual(awb_mz_reader_goto(reader, 5000, &seek2Info), AWB_MZ_OK)
        let seek2Elapsed = CFAbsoluteTimeGetCurrent() - seek2Start
        XCTAssertLessThan(seek2Elapsed, 0.01, "Cached seek took \(seek2Elapsed)s (limit 10ms)")
    }

    func testGotoOutOfBoundsReturnsEnd() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CMinizipBridgeOOBTests-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = root.appending(path: "small.zip")

        var writer: OpaquePointer?
        XCTAssertEqual(archiveURL.withUnsafeFileSystemRepresentation {
            awb_mz_writer_open($0, &writer)
        }, AWB_MZ_OK)
        let payload = Data("x".utf8)
        XCTAssertEqual("only.txt".withCString {
            awb_mz_writer_open_entry(writer, $0, UInt64(payload.count), 0)
        }, AWB_MZ_OK)
        XCTAssertEqual(payload.withUnsafeBytes {
            awb_mz_writer_write_entry(writer, $0.bindMemory(to: UInt8.self).baseAddress, Int32($0.count))
        }, Int32(payload.count))
        XCTAssertEqual(awb_mz_writer_close_entry(writer), AWB_MZ_OK)
        XCTAssertEqual(awb_mz_writer_close(&writer), AWB_MZ_OK)

        var reader: OpaquePointer?
        XCTAssertEqual(archiveURL.withUnsafeFileSystemRepresentation {
            awb_mz_reader_open($0, &reader)
        }, AWB_MZ_OK)
        defer { awb_mz_reader_close(&reader) }

        var info = awb_mz_entry_info()
        // Entry 0 should work
        XCTAssertEqual(awb_mz_reader_goto(reader, 0, &info), AWB_MZ_OK)
        // Entry 1 is out of bounds
        XCTAssertEqual(awb_mz_reader_goto(reader, 1, &info), AWB_MZ_END)
        // Large ordinal is out of bounds
        XCTAssertEqual(awb_mz_reader_goto(reader, 99999, &info), AWB_MZ_END)
    }
}
