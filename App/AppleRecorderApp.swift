import SwiftUI
import Core
import Capture
import Transcribe
import Enhance
import Output
import Theme
import EditorKit
import Pipeline

@main
struct AppleRecorderApp: App {
    @State private var model = AppModel()

    init() {
        SelfTest.runIfRequested()
    }

    var body: some Scene {
        WindowGroup("Apple Recorder") {
            RootView().environment(model).frame(minWidth: 760, minHeight: 520)
        }
    }
}
