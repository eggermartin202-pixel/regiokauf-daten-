import SwiftUI

@main
struct KornApp: App {
    var body: some Scene {
        WindowGroup {
            CameraScreen()
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
