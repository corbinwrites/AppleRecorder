import AppKit
import CoreGraphics
import Foundation

let pid = pid_t(CommandLine.arguments.dropFirst().first ?? "81007") ?? 81007
guard let app = NSRunningApplication(processIdentifier: pid), app.activate(options: [.activateAllWindows]) else {
    fputs("Could not activate Obsidian PID \(pid)\n", stderr)
    exit(1)
}
let source = CGEventSource(stateID: .hidSystemState)
for keyDown in [true, false] {
    let event = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: keyDown) // Escape
    event?.post(tap: .cghidEventTap)
}
print("Activated Obsidian PID \(pid) and pressed Escape")
