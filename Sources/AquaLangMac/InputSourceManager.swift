import Foundation
import Carbon

final class InputSourceManager {
    enum Error: Swift.Error {
        case currentSourceUnavailable
        case noAlternatives
        case selectFailed
    }

    func currentSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    func switchToNextSource() throws {
        guard let current = currentSource() else {
            throw Error.currentSourceUnavailable
        }

        let properties = [kTISPropertyInputSourceIsSelectCapable: kCFBooleanTrue] as CFDictionary
        guard
            let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource],
            !list.isEmpty
        else {
            throw Error.noAlternatives
        }

        guard
        let currentIDPtr = TISGetInputSourceProperty(current, kTISPropertyInputSourceID)
        else {
               throw Error.currentSourceUnavailable
        } 

       let currentID = Unmanaged<CFTypeRef>.fromOpaque(currentIDPtr).takeUnretainedValue()

       let currentIndex = list.firstIndex {
          guard let candidateIDPtr = TISGetInputSourceProperty($0, kTISPropertyInputSourceID) else { return false }
          let candidateID = Unmanaged<CFTypeRef>.fromOpaque(candidateIDPtr).takeUnretainedValue()
          return CFEqual(candidateID, currentID)
       } ?? -1

        guard list.count > 1 else {
            throw Error.noAlternatives
        }

        let next = list[(currentIndex + 1) % list.count]
        let status = TISSelectInputSource(next)
        guard status == noErr else {
            throw Error.selectFailed
        }
    }
}

