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
        fatalError("TODO")
    }
}
