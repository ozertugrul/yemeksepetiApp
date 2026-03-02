import SwiftUI

@main
struct YemeksepetiApp: App {
    @StateObject var viewModel = AppViewModel()

    init() {
        print("YemeksepetiApp launched — JWT auth aktif")
    }

    var body: some Scene {
        WindowGroup {
            MainView(appViewModel: viewModel)
        }
    }
}
