import AppKit
import CoreGraphics
import Foundation

let pid = pid_t(CommandLine.arguments.dropFirst().first ?? "81007") ?? 81007
guard let app = NSRunningApplication(processIdentifier: pid), app.activate(options: [.activateAllWindows]) else {
    fputs("Could not activate Obsidian PID \(pid)\n", stderr)
    exit(1)
}
Thread.sleep(forTimeInterval: 0.4)
let point = CGPoint(x: 160, y: 840) // vault name/switcher in the observed 1440x900 window
for type in [CGEventType.leftMouseDown, .leftMouseUp] {
    let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
    event?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.05)
}
print("Activated Obsidian PID \(pid) and clicked the observed vault switcher at \(point)")
