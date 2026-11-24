import CoreGraphics
import Foundation

let x = CGFloat(Double(CommandLine.arguments.dropFirst().first ?? "720") ?? 720)
let y = CGFloat(Double(CommandLine.arguments.dropFirst(2).first ?? "170") ?? 170)
let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)
for type in [CGEventType.leftMouseDown, .leftMouseUp] {
    let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
    event?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.05)
}
print("Clicked current screen point \(point) without app activation")
