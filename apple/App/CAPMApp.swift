import SwiftUI

@main
struct CAPMApp: App {
    #if os(macOS)
    init() { _ = Actualizador.control }              // arranca Sparkle con la app
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView().preferredColorScheme(.dark)   // Neural Noir, el mismo look que la web
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 840)
        .windowStyle(.hiddenTitleBar)
        .commands { MenuActualizar() }
        #endif
    }
}
