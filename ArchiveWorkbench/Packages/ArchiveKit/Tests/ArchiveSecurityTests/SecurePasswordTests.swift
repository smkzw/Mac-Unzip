import ArchiveSecurity
import XCTest

final class SecurePasswordTests: XCTestCase {
    func testBasicCreationAndAccess() {
        let password = SecurePassword("my-secret")
        XCTAssertEqual(password.count, 9)
        XCTAssertFalse(password.isEmpty)

        password.withCString { ptr in
            XCTAssertEqual(String(cString: ptr), "my-secret")
        }
    }

    func testEmptyPassword() {
        let password = SecurePassword("")
        XCTAssertEqual(password.count, 0)
        XCTAssertTrue(password.isEmpty)

        password.withCString { ptr in
            XCTAssertEqual(String(cString: ptr), "")
        }
    }

    func testUnicodePassword() {
        let password = SecurePassword("密码测试🔑")
        XCTAssertFalse(password.isEmpty)

        password.withCString { ptr in
            XCTAssertEqual(String(cString: ptr), "密码测试🔑")
        }
    }

    func testBytesCreation() {
        let bytes: [UInt8] = [0x48, 0x65, 0x6C, 0x6C, 0x6F] // "Hello"
        let password = SecurePassword("Hello")
        XCTAssertEqual(password.count, 5)

        password.withBytes { buffer in
            XCTAssertEqual(buffer.map { $0 }, bytes)
        }
    }

    func testDescriptionDoesNotLeakPassword() {
        let password = SecurePassword("super-secret-password-12345")
        XCTAssertFalse(password.description.contains("super-secret"))
        XCTAssertFalse(password.debugDescription.contains("super-secret"))
        XCTAssertTrue(password.description.contains("•"))
        XCTAssertTrue(password.debugDescription.contains("count:"))
    }

    func testStringInterpolationDoesNotLeak() {
        let password = SecurePassword("leak-check")
        let interpolated = "\(password)"
        XCTAssertFalse(interpolated.contains("leak-check"))
    }

    func testWithCStringProvidesNullTermination() {
        let password = SecurePassword("abc")
        password.withCString { ptr in
            // Verify null termination by checking the 4th byte
            XCTAssertEqual(ptr[0], CChar(UInt8(ascii: "a")))
            XCTAssertEqual(ptr[1], CChar(UInt8(ascii: "b")))
            XCTAssertEqual(ptr[2], CChar(UInt8(ascii: "c")))
            XCTAssertEqual(ptr[3], 0)
        }
    }

    func testSendableConformance() {
        // Verify SecurePassword can cross actor boundaries
        let password = SecurePassword("cross-actor")
        let expectation = expectation(description: "actor crossing")

        Task {
            // Access from a different task/actor context
            password.withCString { ptr in
                XCTAssertEqual(String(cString: ptr), "cross-actor")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testMultipleAccessesReturnSameContent() {
        let password = SecurePassword("consistent")
        for _ in 0..<10 {
            password.withCString { ptr in
                XCTAssertEqual(String(cString: ptr), "consistent")
            }
        }
    }
}
