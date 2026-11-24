import AppKit
import CoreGraphics
import Foundation

let pid = pid_t(CommandLine.arguments.dropFirst().first ?? "81007") ?? 81007
let app = NSRunningApplication(processIdentifier: pid)
guard let app, app.activate(options: [.activateAllWindows]) else {
    fputs("Could not activate Obsidian PID \(pid)\n", stderr)
    exit(1)
}
Thread.sleep(forTimeInterval: 0.5)
let source = CGEventSource(stateID: .hidSystemState)
let keyCode: CGKeyCode = 35 // P
let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
down?.flags = [.maskCommand]
down?.post(tap: .cghidEventTap)
let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
up?.flags = [.maskCommand]
up?.post(tap: .cghidEventTap)
print("Activated Obsidian PID \(pid) and sent Command-P")
