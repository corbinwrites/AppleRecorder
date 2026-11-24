import CoreGraphics
import Foundation

let text = CommandLine.arguments.dropFirst().first ?? ""
let source = CGEventSource(stateID: .hidSystemState)
let units = Array(text.utf16)
let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
units.withUnsafeBufferPointer { buffer in
    down?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
}
down?.post(tap: .cghidEventTap)
let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
up?.post(tap: .cghidEventTap)
print("Typed \(text.debugDescription) into the currently focused field; no app activation performed")
