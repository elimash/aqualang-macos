// AquaLangMacOS/Sources/AquaLangMac/ReplayEngine.swift
import Foundation
import CoreGraphics
import AquaLangCore

final class ReplayEngine {
    private let source = CGEventSource(stateID: .hidSystemState)

    func replaceBufferedText(with strokes: [KeyStroke], typedCount: Int, marker: Int64) {
        guard typedCount > 0 else { return }
        sendBackspaces(typedCount, marker: marker)
        for stroke in strokes {
            emit(keyCode: stroke.keyCode, flags: stroke.flags, marker: marker)
        }
    }

    private func sendBackspaces(_ count: Int, marker: Int64) {
        for _ in 0..<count {
            emit(keyCode: 51, flags: [], marker: marker)
        }
    }

    private func emit(keyCode: CGKeyCode, flags: CGEventFlags, marker: Int64) {
        guard let source else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        down?.setIntegerValueField(.eventSourceUserData, value: marker)
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        up?.setIntegerValueField(.eventSourceUserData, value: marker)
        up?.post(tap: .cghidEventTap)
    }
}

