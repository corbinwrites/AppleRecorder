import CoreGraphics
import Foundation

let source = CGEventSource(stateID: .hidSystemState)
let keyCode: CGKeyCode = 36 // Return
for keyDown in [true, false] {
    let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
    event?.post(tap: .cghidEventTap)
}
print("Pressed Return in the currently focused Obsidian control")
