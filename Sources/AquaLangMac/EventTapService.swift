// AquaLangMacOS/Sources/AquaLangMac/EventTapService.swift
import Foundation
import CoreGraphics
import ApplicationServices
import AquaLangCore

final class EventTapService {
    private let debugEnabled = false

    private struct LastConversion {
        let strokes: [KeyStroke]
        let typedCount: Int
        let sourceBeforeID: String
        let sourceAfterID: String
    }

    private func dlog(_ message: String) {
        if debugEnabled {
            print("[AquaTap] \(message)")
        }
    }

    private let buffer = RecentKeyBuffer(maxSize: 220)
    private let triggerDetector: DoubleModifierDetector
    private let sourceManager = InputSourceManager()
    private let replayEngine = ReplayEngine()
    private let replayEventMarker: Int64 = 0x41514C4D

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isReplaying = false
    private var lastConversion: LastConversion?

    // reliability guards (ported behavior intent from Windows stateful trigger handling)
    private var isTriggerCurrentlyDown = false
    private var lastCompletedTapAt: TimeInterval?
    private var lastTriggerAt: TimeInterval = 0

    private let doubleTapThresholdSeconds: TimeInterval = 0.42
    private let triggerCooldownSeconds: TimeInterval = 0.75
    private let layoutSwitchVerifyRetries = 12
    private let layoutSwitchVerifyDelayUsec: useconds_t = 25_000
    private let fieldBoundaryKeyCodes: Set<CGKeyCode> = [36, 48] // Enter, Tab

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
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)
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
            dlog("tap disabled by timeout; re-enabling")
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return Unmanaged.passUnretained(event)
        }

       if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            dlog("field boundary by mouse click; clearing buffer")
            buffer.clear()
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        if isReplaying {
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == replayEventMarker {
            dlog("ignoring synthetic replay event (pass-through)")
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        dlog("type=\(type.rawValue) key=\(keyCode) flags=\(event.flags.rawValue) replaying=\(isReplaying)")

        if type == .flagsChanged && triggerDetector.shouldTrack(keyCode: keyCode) {
            let now = CFAbsoluteTimeGetCurrent()
            if shouldTriggerOnModifierEdge(event: event, now: now) {
                dlog("TRIGGER FIRED")
                lastTriggerAt = now
                triggerLanguageReplace()
                return nil
            }
            return nil
        }

        if type == .keyDown {
           if fieldBoundaryKeyCodes.contains(keyCode) {
                dlog("field boundary key=\(keyCode); clearing buffer")
                buffer.clear()
                return Unmanaged.passUnretained(event)
            }
            let stroke = KeyStroke(keyCode: keyCode, flags: event.flags)
            buffer.append(stroke)
        }

        return Unmanaged.passUnretained(event)
    }

    private func shouldTriggerOnModifierEdge(event: CGEvent, now: TimeInterval) -> Bool {
        if (now - lastTriggerAt) < triggerCooldownSeconds {
            dlog("edge ignored by cooldown")
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
            return true
        }

        lastCompletedTapAt = now
        return false
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
        case .function:
            return .maskSecondaryFn
        }
    }

    private func triggerLanguageReplace() {
        let snapshot = buffer.snapshot()
        let characterCount = buffer.typedCharacterCount

        if characterCount == 0 {
            guard let lastConversion else {
                dlog("replace skipped: empty buffer and no last conversion")
                return
            }

            dlog("empty buffer trigger: cycling last conversion")
            cycleLastConversion(lastConversion)
            return
        }

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
                dlog("replace skipped: source did not change")
                return
            }

            // verify source switch before replay, similar to Windows retry/timer semantics
            var verified = false
            for _ in 0..<layoutSwitchVerifyRetries {
                usleep(layoutSwitchVerifyDelayUsec)
                if sourceManager.currentSourceID() == targetID {
                    verified = true
                    break
                }
            }

            if !verified {
                dlog("source verified=false")
                // fallback to previous behavior timing if source id cannot be verified in time
                usleep(80_000)
            }

            dlog("replay begin")
            replayEngine.replaceBufferedText(with: snapshot, typedCount: characterCount, marker: replayEventMarker)

            if let beforeID {
                lastConversion = LastConversion(strokes: snapshot, typedCount: characterCount, sourceBeforeID: beforeID, sourceAfterID: targetID)
            }
        } catch {
            fputs("AquaLangMac error: \(error)\n", stderr)
        }
    }
    private func cycleLastConversion(_ conversion: LastConversion) {
        isReplaying = true
        defer {
            triggerDetector.reset()
            isReplaying = false
        }

        do {
            dlog("cycle start chars=\(conversion.typedCount)")
            let current = sourceManager.currentSourceID()
            dlog("cycle current source=\(current ?? "nil") expected after=\(conversion.sourceAfterID)")

            if current != conversion.sourceAfterID {
                dlog("cycle skipped: current source is not the converted source")
                return
            }

            let targetID = try sourceManager.switchToNextSource()
            dlog("cycle target source=\(targetID)")

            var verified = false
            for _ in 0..<layoutSwitchVerifyRetries {
                usleep(layoutSwitchVerifyDelayUsec)
                if sourceManager.currentSourceID() == targetID {
                    verified = true
                    break
                }
            }

            if !verified {
                dlog("cycle source verified=false")
                usleep(80_000)
            }

            replayEngine.replaceBufferedText(with: conversion.strokes, typedCount: conversion.typedCount, marker: replayEventMarker)
            buffer.clear()
            lastConversion = LastConversion(
                strokes: conversion.strokes,
                typedCount: conversion.typedCount,
                sourceBeforeID: conversion.sourceBeforeID,
                sourceAfterID: targetID
            )
            dlog("cycle replay done")
        } catch {
            fputs("AquaLangMac error: \(error)\n", stderr)
        }
    }

}

