import XCTest
@testable import AquaLangCore

final class DoubleModifierDetectorTests: XCTestCase {
    func testDoubleModifierWithinThresholdTriggers() {
        let detector = DoubleModifierDetector(trigger: .shift, thresholdSeconds: 0.5)
        XCTAssertFalse(detector.registerModifierDown(now: 1.0))
        XCTAssertTrue(detector.registerModifierDown(now: 1.3))
    }

    func testDoubleModifierOutsideThresholdDoesNotTrigger() {
        let detector = DoubleModifierDetector(trigger: .shift, thresholdSeconds: 0.3)
        XCTAssertFalse(detector.registerModifierDown(now: 1.0))
        XCTAssertFalse(detector.registerModifierDown(now: 1.31))
    }

    func testControlTriggerTracksControlOnly() {
        let detector = DoubleModifierDetector(trigger: .control)
        XCTAssertTrue(detector.shouldTrack(keyCode: 59))
        XCTAssertTrue(detector.shouldTrack(keyCode: 62))
        XCTAssertFalse(detector.shouldTrack(keyCode: 56))
    }

    func testParseTriggerAliases() {
        XCTAssertEqual(ModifierTrigger.parse("ctrl"), .control)
        XCTAssertEqual(ModifierTrigger.parse("cmd"), .command)
        XCTAssertEqual(ModifierTrigger.parse("alt"), .option)
        XCTAssertEqual(ModifierTrigger.parse(nil), .shift)
        XCTAssertEqual(ModifierTrigger.parse("unknown"), .shift)
    }
}

