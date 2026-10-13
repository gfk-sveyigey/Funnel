import SwiftUI

@main
struct FunnelApp: App {

    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .onChange(of: scenePhase) { _, newPhase in
            model.scenePhaseChanged(newPhase)
        }
    }
}
