import Foundation
import Core

public struct AudioProcessInfo: Sendable, Equatable {
    public var objectID: UInt32
    public var pid: Int32
    public var bundleID: String?
    public var executablePath: String?
    public var isRunningOutput: Bool

    public init(objectID: UInt32, pid: Int32, bundleID: String? = nil, executablePath: String? = nil, isRunningOutput: Bool) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.executablePath = executablePath
        self.isRunningOutput = isRunningOutput
    }
}

public struct AppEntry: Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var objectIDs: [UInt32]
    public var isRunningOutput: Bool

    public init(id: String, displayName: String, objectIDs: [UInt32], isRunningOutput: Bool) {
        self.id = id
        self.displayName = displayName
        self.objectIDs = objectIDs
        self.isRunningOutput = isRunningOutput
    }
}

public enum ProcessCatalog {
    public static func group(_ procs: [AudioProcessInfo]) -> [AppEntry] {
        struct Group {
            var displayName: String
            var objectIDs: [UInt32]
            var isRunningOutput: Bool
        }
        var groups: [String: Group] = [:]
        for process in procs {
            let key: String
            let displayName: String
            if let path = process.executablePath, !path.isEmpty {
                let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
                if let index = components.firstIndex(where: { $0.lowercased().hasSuffix(".app") }) {
                    let bundlePath = components.prefix(index + 1).joined(separator: "/")
                    key = "path:\(bundlePath)"
                    displayName = String(components[index].dropLast(4))
                } else if let bundleID = process.bundleID, !bundleID.isEmpty {
                    (key, displayName) = bundleIdentity(bundleID)
                } else {
                    key = "pid:\(process.pid)"
                    displayName = "Process \(process.pid)"
                }
            } else if let bundleID = process.bundleID, !bundleID.isEmpty {
                (key, displayName) = bundleIdentity(bundleID)
            } else {
                key = "pid:\(process.pid)"
                displayName = "Process \(process.pid)"
            }
            var group = groups[key] ?? Group(displayName: displayName, objectIDs: [], isRunningOutput: false)
            group.objectIDs.append(process.objectID)
            group.isRunningOutput = group.isRunningOutput || process.isRunningOutput
            groups[key] = group
        }
        return groups.map { key, group in
            AppEntry(id: key, displayName: group.displayName, objectIDs: group.objectIDs.sorted(), isRunningOutput: group.isRunningOutput)
        }.sorted {
            if $0.isRunningOutput != $1.isRunningOutput { return $0.isRunningOutput }
            let comparison = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return $0.id < $1.id
        }
    }

    private static func bundleIdentity(_ bundleID: String) -> (String, String) {
        let components = bundleID.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let helperIndex = components.firstIndex { $0.caseInsensitiveCompare("helper") == .orderedSame }
        let root = helperIndex.map { components.prefix($0).joined(separator: ".") } ?? bundleID
        let name = root.split(separator: ".").last.map(String.init) ?? bundleID
        return ("bundle:\(root.lowercased())", name)
    }
}
