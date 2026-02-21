import SwiftUI
import FirebaseCore

@main
struct YemeksepetiApp: App {
    @StateObject var viewModel = AppViewModel()

    init() {
        FirebaseApp.configure()
        // Auth.auth().useEmulator(withHost: "localhost", port: 9099) // Uncomment if using emulator
        print("Firebase configured!")
    }

    var body: some Scene {
        WindowGroup {
            MainView(appViewModel: viewModel)
        }
    }
}
