import AppKit
import CoreGraphics
import Foundation

let pid = pid_t(CommandLine.arguments.dropFirst().first ?? "81007") ?? 81007
let query = CommandLine.arguments.dropFirst(2).first ?? ""
guard let app = NSRunningApplication(processIdentifier: pid), app.activate(options: [.activateAllWindows]) else {
    fputs("Could not activate Obsidian PID \(pid)\n", stderr)
    exit(1)
}
Thread.sleep(forTimeInterval: 0.2)
let source = CGEventSource(stateID: .hidSystemState)
let shortcutDown = CGEvent(keyboardEventSource: source, virtualKey: 35, keyDown: true) // P
shortcutDown?.flags = [.maskCommand]
shortcutDown?.post(tap: .cghidEventTap)
let shortcutUp = CGEvent(keyboardEventSource: source, virtualKey: 35, keyDown: false)
shortcutUp?.flags = [.maskCommand]
shortcutUp?.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.2)
let units = Array(query.utf16)
let textDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
units.withUnsafeBufferPointer { buffer in
    textDown?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
}
textDown?.post(tap: .cghidEventTap)
let textUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
textUp?.post(tap: .cghidEventTap)
print("Opened Obsidian command palette and searched for \(query.debugDescription)")
