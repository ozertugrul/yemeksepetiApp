import SwiftUI

@main
struct YemeksepetiApp: App {
    @StateObject var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            MainView(appViewModel: viewModel)
        }
    }
}
