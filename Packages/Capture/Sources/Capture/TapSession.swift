import Foundation
import CoreAudio
import AVFoundation
import Core

public enum CaptureError: Error, Sendable, Equatable {
    case osStatus(String, Int32)
    case noFormat
    case deviceNotFound
}

public final class TapSession: @unchecked Sendable {
    public let ring: RingBuffer
    public private(set) var sampleRate: Double = 48_000
    public private(set) var channels = 1
    public var firstHostTime: UInt64 {
        fatalError("TODO")
    }

    public init(processObjectIDs: [UInt32], ringSeconds: Double = 10) throws {
        throw TODO.notImplemented
    }

    public func start() throws {
        throw TODO.notImplemented
    }

    public func stop() {
        fatalError("TODO")
    }
}

public final class MicSession: @unchecked Sendable {
    public let ring: RingBuffer
    public private(set) var sampleRate: Double = 48_000
    public private(set) var channels = 1
    public var firstHostTime: UInt64 {
        fatalError("TODO")
    }

    public init() throws {
        throw TODO.notImplemented
    }

    public func start() throws {
        throw TODO.notImplemented
    }

    public func stop() {
        fatalError("TODO")
    }
}

public enum AudioProcessEnumerator {
    public static func list() -> [AudioProcessInfo] {
        fatalError("TODO")
    }
}
