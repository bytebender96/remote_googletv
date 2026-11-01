import SwiftUI

@main
struct RemoteTVApp: App {
    @StateObject private var store = DeviceStore()

    var body: some Scene {
        WindowGroup {
            DeviceListView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
