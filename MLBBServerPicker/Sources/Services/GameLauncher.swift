import Foundation
import UIKit

/// Launches MLBB if it is installed, otherwise sends the user to the store.
@MainActor
enum GameLauncher {

    private static let schemes = ["mobilelegends://", "mlbb://"]
    static let garenaGlobalStore = URL(string: "https://apps.apple.com/app/id1202080142")!

    static var isInstalled: Bool {
        schemes.contains { scheme in
            guard let url = URL(string: scheme) else { return false }
            return UIApplication.shared.canOpenURL(url)
        }
    }

    @discardableResult
    static func launch() -> Bool {
        for scheme in schemes {
            guard let url = URL(string: scheme) else { continue }
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return true
            }
        }
        UIApplication.shared.open(garenaGlobalStore)
        return false
    }
}