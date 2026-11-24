import AppKit
import CoreGraphics
import Foundation

let pid = pid_t(CommandLine.arguments.dropFirst().first ?? "81007") ?? 81007
guard let app = NSRunningApplication(processIdentifier: pid), app.activate(options: [.activateAllWindows]) else {
    fputs("Could not activate Obsidian PID \(pid)\n", stderr)
    exit(1)
}
let source = CGEventSource(stateID: .hidSystemState)
let keyCode: CGKeyCode = 6 // Z
let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
down?.flags = [.maskCommand]
down?.post(tap: .cghidEventTap)
let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
up?.flags = [.maskCommand]
up?.post(tap: .cghidEventTap)
print("Sent Command-Z to undo the text inserted by the Obsidian navigation probe")
