import Foundation
import CoreGraphics
import AquaLangCore

final class ReplayEngine {
    private let source = CGEventSource(stateID: .hidSystemState)

    func replaceBufferedText(with strokes: [KeyStroke], typedCount: Int) {
        guard typedCount > 0 else { return }
        sendBackspaces(typedCount)
        for stroke in strokes {
            emit(keyCode: stroke.keyCode, flags: stroke.flags)
        }
    }

    private func sendBackspaces(_ count: Int) {
        for _ in 0..<count {
            emit(keyCode: 51, flags: [])
        }
    }

    private func emit(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }
}

