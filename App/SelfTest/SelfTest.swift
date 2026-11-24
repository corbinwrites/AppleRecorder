import Foundation

public enum SelfTest {
    public static func runIfRequested() {
        guard CommandLine.arguments.contains("--selftest") else { return }
    }
}
