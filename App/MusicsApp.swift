import SwiftUI

@main
struct MusicsApp: App {
    @State private var model = AppModel()

    init() {
        Typeface.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
