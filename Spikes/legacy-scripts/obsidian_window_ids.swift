import Foundation
import CoreGraphics

let options: CGWindowListOption = [.optionOnScreenOnly]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    guard let owner = window[kCGWindowOwnerName as String] as? String,
          owner.localizedCaseInsensitiveContains("Obsidian") else { continue }
    let id = window[kCGWindowNumber as String] ?? "unknown"
    let title = window[kCGWindowName as String] as? String ?? "(untitled)"
    let bounds = window[kCGWindowBounds as String] ?? "unknown"
    print("window=\(id) owner=\(owner) title=\(title) bounds=\(bounds)")
}
