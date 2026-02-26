import Foundation
import Carbon

final class InputSourceManager {
    private let debugEnabled = false 

    enum Error: Swift.Error {
        case currentSourceUnavailable
        case noAlternatives
        case selectFailed
        case targetIdUnavailable
    }

    func currentSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    func currentSourceID() -> String? {
        guard
            let current = currentSource(),
            let currentIDPtr = TISGetInputSourceProperty(current, kTISPropertyInputSourceID)
        else {
            return nil
        }

        let currentID = Unmanaged<CFTypeRef>.fromOpaque(currentIDPtr).takeUnretainedValue()
        return currentID as? String
    }

    @discardableResult
    func switchToNextSource() throws -> String {
        guard let current = currentSource() else {
            throw Error.currentSourceUnavailable
        }

        let properties = [kTISPropertyInputSourceIsSelectCapable: kCFBooleanTrue] as CFDictionary
        guard
            let rawList = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource]
        else {
            throw Error.noAlternatives
        }

        if debugEnabled {
            print("[AquaTap] sources count=\(rawList.count)")
        }

        let list = rawList.filter(isTypingInputSource)
        if debugEnabled {
            print("[AquaTap] candidate typing sources=\(list.count)")
        }
        guard !list.isEmpty else {
            throw Error.noAlternatives
        }

        guard
            let currentIDPtr = TISGetInputSourceProperty(current, kTISPropertyInputSourceID)
        else {
            throw Error.currentSourceUnavailable
        }

        let currentID = Unmanaged<CFTypeRef>.fromOpaque(currentIDPtr).takeUnretainedValue()
        let currentIDString = String(describing: currentID)

        if debugEnabled {
            print("[AquaTap] currentID raw=\(currentID)")
        }

        let currentIndex = list.firstIndex { source in
            guard let candidateIDPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
            let candidateID = Unmanaged<CFTypeRef>.fromOpaque(candidateIDPtr).takeUnretainedValue()
            if debugEnabled {
                print("[AquaTap] candidateID raw=\(candidateID)")
            }
            return String(describing: candidateID) == currentIDString
        }
        guard let currentIndex else {
            throw Error.currentSourceUnavailable
        }

        if debugEnabled {
            print("[AquaTap] resolved currentIndex=\(currentIndex)")
            print("[AquaTap] switching to index=\((currentIndex + 1) % list.count)")
        }

        guard list.count > 1 else {
            throw Error.noAlternatives
        }

        let next = list[(currentIndex + 1) % list.count]
        let status = TISSelectInputSource(next)
        guard status == noErr else {
            throw Error.selectFailed
        }

        guard let targetIDPtr = TISGetInputSourceProperty(next, kTISPropertyInputSourceID) else {
            throw Error.targetIdUnavailable
        }
        let targetID = Unmanaged<CFTypeRef>.fromOpaque(targetIDPtr).takeUnretainedValue()
        guard let targetIDString = targetID as? String else {
            throw Error.targetIdUnavailable
        }

        if debugEnabled {
            print("[AquaTap] target source=\(targetIDString)")
        }

        return targetIDString
    }

    private func isTypingInputSource(_ source: TISInputSource) -> Bool {
        guard
            let typePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceType),
            let sourceIDPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else {
            return false
        }

        let typeValue = Unmanaged<CFTypeRef>.fromOpaque(typePtr).takeUnretainedValue()
        let sourceIDValue = Unmanaged<CFTypeRef>.fromOpaque(sourceIDPtr).takeUnretainedValue()

        let isKeyboardType = CFEqual(typeValue, kTISTypeKeyboardLayout) || CFEqual(typeValue, kTISTypeKeyboardInputMode)
        guard isKeyboardType else {
            return false
        }

        let sourceID = String(describing: sourceIDValue)
        let excludedIDs = ["CharacterPalette", "Emoji", "Handwriting"]
        if excludedIDs.contains(where: { sourceID.localizedCaseInsensitiveContains($0) }) {
            return false
        }

        if let languagesPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
           let languages = Unmanaged<CFTypeRef>.fromOpaque(languagesPtr).takeUnretainedValue() as? [String],
           languages.isEmpty {
            return false
        }

        if let asciiCapablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable),
           let asciiCapable = Unmanaged<CFTypeRef>.fromOpaque(asciiCapablePtr).takeUnretainedValue() as? Bool,
           !asciiCapable,
           sourceID.localizedCaseInsensitiveContains("Palette") {
            return false
        }

        return true
    }
}

