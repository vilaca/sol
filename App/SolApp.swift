import SwiftUI

@main
struct SolApp: App {
    @StateObject private var model = GameModel(launch: .current)

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-cardGallery") {
                CardGallery()
            } else {
                GameView(model: model)
            }
            #else
            GameView(model: model)
            #endif
        }
    }
}
