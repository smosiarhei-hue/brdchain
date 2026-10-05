import SwiftUI

@main
struct MLBBServerPickerApp: App {
    @StateObject private var scanner = ServerScanner()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scanner)
        }
    }
}