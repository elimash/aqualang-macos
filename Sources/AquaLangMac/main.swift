import Foundation
import ApplicationServices
import AquaLangCore

let trusted = AXIsProcessTrustedWithOptions([
    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true as CFBoolean
] as CFDictionary)

if !trusted {
    print("Accessibility permission is required. Enable it in System Settings → Privacy & Security → Accessibility.")
}

let trigger = ModifierTrigger.parse(ProcessInfo.processInfo.environment["AQUALANG_TRIGGER"])
let service = EventTapService(trigger: trigger)

do {
    try service.start()
    print("AquaLangMac running. Double-press \(service.trigger.rawValue.capitalized) to retype last buffered text in the next input language.")
    CFRunLoopRun()
} catch {
    fputs("Failed to start AquaLangMac: \(error)\n", stderr)
    exit(1)
}

