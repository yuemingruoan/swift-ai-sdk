import AppleHostExampleSupport
import SwiftUI

@main
struct AppleHostExampleApp: App {
    @State private var model: AppleHostExampleModel

    init() {
        do {
            _model = State(initialValue: try AppleHostExampleModel.live())
        } catch {
            fatalError("Failed to initialize AppleHostExampleModel: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("Apple Host Example") {
            AppleHostExampleRootView(model: model)
                .frame(minWidth: 1040, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1220, height: 820)
    }
}
