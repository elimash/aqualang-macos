import XCTest
import CoreGraphics
@testable import AquaLangCore

final class RecentKeyBufferTests: XCTestCase {
    func testBackspaceCompensation() {
        let buffer = RecentKeyBuffer(maxSize: 50)
        buffer.append(KeyStroke(keyCode: 0, flags: []))   // a
        buffer.append(KeyStroke(keyCode: 11, flags: []))  // b
        buffer.append(KeyStroke(keyCode: 51, flags: []))  // backspace
        buffer.append(KeyStroke(keyCode: 8, flags: []))   // c

        XCTAssertEqual(buffer.typedCharacterCount, 2)
    }

    func testIgnoresModifierOnly() {
        let buffer = RecentKeyBuffer(maxSize: 50)
        buffer.append(KeyStroke(keyCode: 56, flags: [.maskShift])) // shift
        buffer.append(KeyStroke(keyCode: 0, flags: []))

        XCTAssertEqual(buffer.snapshot().count, 1)
    }

    func testMaxSizeTrimming() {
        let buffer = RecentKeyBuffer(maxSize: 20)
        for i in 0..<30 {
            buffer.append(KeyStroke(keyCode: CGKeyCode(i % 12), flags: []))
        }
        XCTAssertEqual(buffer.snapshot().count, 20)
    }
}

