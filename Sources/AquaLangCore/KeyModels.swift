import Foundation
import CoreGraphics

public struct KeyStroke: Equatable, Sendable {
    public let keyCode: CGKeyCode
    public let flags: CGEventFlags

    private static let ignoredNonTextKeyCodes: Set<CGKeyCode> = [
        36, // return / enter
        48, // tab
        123, 124, 125, 126, // arrow keys
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, // F1-F10
        103, 111, 105, 107, 113, 106, 64, 79, 80, 90 // F11-F20
    ]


    public init(keyCode: CGKeyCode, flags: CGEventFlags) {
        self.keyCode = keyCode
        self.flags = flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
    }

    public var isBackspace: Bool {
        keyCode == 51
    }

    public var isModifierOnly: Bool {
        ModifierTrigger.modifierKeyCodes.contains(keyCode)
    }

    public var shouldIgnoreForBuffer: Bool {
            isModifierOnly || Self.ignoredNonTextKeyCodes.contains(keyCode)
        }
}

public enum ModifierTrigger: String, CaseIterable, Sendable {
    case shift
    case control
    case option
    case command

    public var keyCodes: Set<CGKeyCode> {
        switch self {
        case .shift:
            return [56, 60] // left/right Shift
        case .control:
            return [59, 62] // left/right Control
        case .option:
            return [58, 61] // left/right Option
        case .command:
            return [55, 54] // left/right Command
        }
    }

    public static var modifierKeyCodes: Set<CGKeyCode> {
        Set(Self.allCases.flatMap { $0.keyCodes })
    }

    public static func parse(_ value: String?) -> ModifierTrigger {
        guard let value else { return .shift }
        switch value.lowercased() {
        case "shift":
            return .shift
        case "ctrl", "control":
            return .control
        case "alt", "option":
            return .option
        case "cmd", "command":
            return .command
        default:
            return .shift
        }
    }
}

public final class RecentKeyBuffer {
    private var strokes: [KeyStroke] = []
    private let maxSize: Int

    public init(maxSize: Int = 160) {
        self.maxSize = max(20, maxSize)
    }

    public func append(_ stroke: KeyStroke) {
        guard !stroke.shouldIgnoreForBuffer else { return }
        strokes.append(stroke)
        if strokes.count > maxSize {
            strokes.removeFirst(strokes.count - maxSize)
        }
    }

    public func snapshot() -> [KeyStroke] {
        strokes
    }

    public func clear() {
        strokes.removeAll(keepingCapacity: true)
    }

    public var typedCharacterCount: Int {
        var count = 0
        for stroke in strokes {
            if stroke.isBackspace {
                count = max(0, count - 1)
            } else {
                count += 1
            }
        }
        return count
    }
}

public final class DoubleModifierDetector {
    private var lastModifierDownAt: TimeInterval?
    public let trigger: ModifierTrigger
    private let thresholdSeconds: TimeInterval

    public init(trigger: ModifierTrigger = .shift, thresholdSeconds: TimeInterval = 0.42) {
        self.trigger = trigger
        self.thresholdSeconds = thresholdSeconds
    }

    public func shouldTrack(keyCode: CGKeyCode) -> Bool {
        trigger.keyCodes.contains(keyCode)
    }

    public func registerModifierDown(now: TimeInterval) -> Bool {
        defer { lastModifierDownAt = now }
        guard let previous = lastModifierDownAt else { return false }
        return (now - previous) <= thresholdSeconds
    }

    public func reset() {
        lastModifierDownAt = nil
    }
}

