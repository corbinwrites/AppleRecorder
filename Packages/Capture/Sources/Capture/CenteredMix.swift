import Foundation
import Core

public enum CenteredMix {
    /// Reads any audio file; writes a 48 kHz mono 16-bit WAV (or AAC if `output` ends in .m4a) whose samples are the mean of all channels. Streams in 1 s blocks.
    public static func write(from source: URL, to output: URL) throws {
        throw TODO.notImplemented
    }
}
