import Foundation
import CoreGraphics
import ApplicationServices
import AquaLangCore

final class EventTapService {


    private let debugTap = true
    private func dlog(_ msg: String) {
        if debugTap { print("[AquaTap] \(msg)") }
    } 

    private let buffer = RecentKeyBuffer(maxSize: 220)
    private let triggerDetector: DoubleModifierDetector
    private let sourceManager = InputSourceManager()
    private let replayEngine = ReplayEngine()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isReplaying = false

    // reliability guards (ported behavior intent from Windows stateful trigger handling)
    private var isTriggerCurrentlyDown = false
    private var lastCompletedTapAt: TimeInterval?
    private var lastTriggerAt: TimeInterval = 0

    private let doubleTapThresholdSeconds: TimeInterval = 0.42
    private let triggerCooldownSeconds: TimeInterval = 0.75
    private let layoutSwitchVerifyRetries = 12
    private let layoutSwitchVerifyDelayUsec: useconds_t = 25_000

    init(trigger: ModifierTrigger = .shift) {
        self.triggerDetector = DoubleModifierDetector(trigger: trigger)
    }

    var trigger: ModifierTrigger {
        triggerDetector.trigger
    }

    func start() throws {
        let mask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let unmanagedSelf = Unmanaged.passUnretained(self)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<EventTapService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: unmanagedSelf.toOpaque()
        ) else {
            throw NSError(domain: "AquaLangMac", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create event tap. Grant Accessibility permission."])
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {

        if type == .tapDisabledByTimeout, let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        if isReplaying {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        dlog("type=\(type.rawValue) key=\(keyCode) flags=\(event.flags.rawValue) replaying=\(isReplaying)")

        if type == .flagsChanged && triggerDetector.shouldTrack(keyCode: keyCode) {
            let now = CFAbsoluteTimeGetCurrent()
            if shouldTriggerOnModifierEdge(event: event, now: now) {
                lastTriggerAt = now
                triggerLanguageReplace()
                return nil
            }
            return nil
        }

        if type == .keyDown {
            let stroke = KeyStroke(keyCode: keyCode, flags: event.flags)
            buffer.append(stroke)
        }

        return Unmanaged.passUnretained(event)
    }


private func shouldTriggerOnModifierEdge(event: CGEvent, now: TimeInterval) -> Bool {

    if (now - lastTriggerAt) < triggerCooldownSeconds {
        return false
    }

    let triggerFlag = eventFlag(for: trigger)
    let isPressedNow = event.flags.contains(triggerFlag)
    dlog("edge now=\(now) lastTriggerAt=\(lastTriggerAt) lastCompletedTapAt=\(String(describing: lastCompletedTapAt)) isDown=\(isTriggerCurrentlyDown) pressedNow=\(isPressedNow)")

    // Press edge
    if isPressedNow {
        if isTriggerCurrentlyDown {
            return false
        }
        isTriggerCurrentlyDown = true
        return false
    }

    // Release edge
    if !isTriggerCurrentlyDown {
        return false
    }
    isTriggerCurrentlyDown = false

    guard let previousTap = lastCompletedTapAt else {
        lastCompletedTapAt = now
        return false
    }

    let isDoubleTap = (now - previousTap) <= doubleTapThresholdSeconds
    if isDoubleTap {
        // consume this sequence and require a fresh pair next time
        lastCompletedTapAt = nil
        dlog("TRIGGER FIRED")
        return true
    } else {
        lastCompletedTapAt = now
        return false
    }
}




    private func eventFlag(for trigger: ModifierTrigger) -> CGEventFlags {
        switch trigger {
        case .shift:
            return .maskShift
        case .control:
            return .maskControl
        case .option:
            return .maskAlternate
        case .command:
            return .maskCommand
        }
    }

private func triggerLanguageReplace() {
    let snapshot = buffer.snapshot()
    let characterCount = buffer.typedCharacterCount
    guard characterCount > 0 else { return }

    isReplaying = true
    defer {
        triggerDetector.reset()
        buffer.clear()
        isReplaying = false
    }

    do {
        dlog("replace start chars=\(characterCount)")
        let beforeID = sourceManager.currentSourceID()
        dlog("before source=\(beforeID ?? "nil")")

        let targetID = try sourceManager.switchToNextSource()
        dlog("target source=\(targetID)")

        if beforeID == targetID {
            dlog("source did not change, aborting replay")
            return
        }

        var verified = false
        for _ in 0..<layoutSwitchVerifyRetries {
            usleep(layoutSwitchVerifyDelayUsec)
            if sourceManager.currentSourceID() == targetID {
                verified = true
                break
            }
        }

        dlog("source verified=\(verified)")

        if !verified {
            usleep(80_000)
        }

        dlog("replay begin")
        replayEngine.replaceBufferedText(with: snapshot, typedCount: characterCount)
    } catch {
        fputs("AquaLangMac error: \(error)\n", stderr)
    }
}




}

