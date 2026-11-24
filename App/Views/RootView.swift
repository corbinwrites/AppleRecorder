import SwiftUI

public struct RootView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        Text("Apple Recorder")
    }
}
