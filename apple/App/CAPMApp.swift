import SwiftUI

@main
struct CAPMApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().preferredColorScheme(.dark)   // Neural Noir, el mismo look que la web
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 840)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
