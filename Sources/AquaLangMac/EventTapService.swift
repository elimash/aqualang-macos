import Foundation
import CoreGraphics
import ApplicationServices
import AquaLangCore

final class EventTapService {
    private let buffer = RecentKeyBuffer(maxSize: 220)
    private let triggerDetector: DoubleModifierDetector
    private let sourceManager = InputSourceManager()
    private let replayEngine = ReplayEngine()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isReplaying = false

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

        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let keyCode = CGKeyCode(code)
        let stroke = KeyStroke(keyCode: keyCode, flags: event.flags)

        if triggerDetector.shouldTrack(keyCode: stroke.keyCode) {
            let triggered = triggerDetector.registerModifierDown(now: CFAbsoluteTimeGetCurrent())
            if triggered {
                triggerLanguageReplace()
                return nil
            }
            return nil
        }

        buffer.append(stroke)
        return Unmanaged.passUnretained(event)
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
            try sourceManager.switchToNextSource()
            usleep(80_000)
            replayEngine.replaceBufferedText(with: snapshot, typedCount: characterCount)
        } catch {
            fputs("AquaLangMac error: \(error)\n", stderr)
        }
    }
}

